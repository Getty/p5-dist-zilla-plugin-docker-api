package Dist::Zilla::Plugin::Docker::API::Client;
# ABSTRACT: Thin adapter around API::Docker
our $VERSION = '0.104';
use Moo;
use Archive::Tar;
use Carp qw( croak );
use Path::Tiny;
use JSON::MaybeXS qw( decode_json );
use MIME::Base64 qw( decode_base64 );

use API::Docker;
use Dist::Zilla::Plugin::Docker::API::Result;

has docker => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
        API::Docker->new;
    },
);

has logger => (
    is       => 'ro',
    required => 1,
);

has logger_fatal => (
    is       => 'ro',
    required => 1,
);

has docker_config_path => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
        $ENV{DOCKER_CONFIG}
            ? Path::Tiny::path($ENV{DOCKER_CONFIG}, 'config.json')
            : Path::Tiny::path($ENV{HOME} // '', '.docker', 'config.json');
    },
);

has _docker_config => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
        my ($self) = @_;
        my $path = $self->docker_config_path;
        return {} unless $path && -r "$path";
        my $data = eval { decode_json(Path::Tiny::path($path)->slurp_utf8) };
        if ($@ || !$data) {
            $self->logger->("Warning: cannot parse $path: $@") if $@;
            return {};
        }
        return $data;
    },
);

# Cheapest round trip that proves an engine is actually listening on the
# socket. Used by the plugin's before_build precheck, so a missing daemon
# is reported before Dist::Zilla does any work rather than after.
sub engine_info {
    my ($self) = @_;

    my $version = eval { $self->docker->system->version };
    croak $@ if $@;
    croak 'the engine returned no version information'
        unless ref $version eq 'HASH';

    my ($engine) = grep { ($_->{Name} // '') =~ /engine/i }
        @{ $version->{Components} // [] };

    return {
        version     => $version->{Version},
        api_version => $version->{ApiVersion},
        engine      => $engine ? $engine->{Name} : undef,
    };
}

# The engine's tag endpoint takes the repository and the tag as two separate
# parameters (POST /images/{name}/tag?repo=&tag=), so a full image reference
# has to be taken apart before it goes over the wire. Passing the whole thing
# as `repo` leaves `tag` empty and the engine fills in its own default:
# podman then rejects `example/app:1.0:latest` with a 500 and every version
# tag is quietly lost. Splitting happens here rather than in API::Docker,
# which mirrors the endpoint and should keep doing so.
sub _split_image_ref {
    my ( $self, $ref ) = @_;

    my $colon = rindex $ref, ':';
    return ( $ref, undef ) if $colon < 0;
    # A colon before the last slash belongs to a registry host:port, not to a
    # tag: registry.example.com:5000/team/app carries no tag at all.
    return ( $ref, undef ) if rindex($ref, '/') > $colon;

    return ( substr($ref, 0, $colon), substr($ref, $colon + 1) );
}

sub build_image {
    my ($self, %arg) = @_;

    my $context = $arg{context_tar};
    my $dockerfile = $arg{dockerfile} // 'Dockerfile';
    my @tags = @{ $arg{tags} // [] };
    my %labels = %{ $arg{labels} // {} };
    my %buildargs = %{ $arg{buildargs} // {} };
    my $pull = $arg{pull} // 0;
    my $nocache = $arg{nocache} // 0;
    my $rm = $arg{rm} // 1;
    my $forcerm = $arg{forcerm} // 1;
    my $target = $arg{target};
    my $network_mode = $arg{network_mode};
    my $platform = $arg{platform};
    my $verbose = $arg{verbose} // 0;

    my $docker = $self->docker;

    my %build_opts = (
        dockerfile => $dockerfile,
        t => @tags ? $tags[0] : undef,
        pull => $pull ? 1 : 0,
        nocache => $nocache ? 1 : 0,
        rm => $rm ? 1 : 0,
        forcerm => $forcerm ? 1 : 0,
    );

    $build_opts{labels} = \%labels if %labels;
    $build_opts{buildargs} = \%buildargs if %buildargs;
    $build_opts{target} = $target if defined $target && length $target;
    $build_opts{networkmode} = $network_mode if defined $network_mode && length $network_mode;
    $build_opts{platform} = $platform if defined $platform && length $platform;

    my $image_id;
    my @processed_tags;

    # Concise mode (default): only forward Dockerfile step headers — both the
    # legacy builder ("Step N/M : ...") and BuildKit ("#N [N/M] ..."). Skip the
    # noisy intermediate container chatter. Verbose mode forwards every line.
    # The line buffer is used in both modes so the Dist::Zilla logger (which
    # appends its own newline) doesn't get a stream chunk with a trailing \n.
    my $line_buf = '';
    my $progress_cb = sub {
        my ($event) = @_;
        if ($event->{errorDetail}) {
            $self->logger_fatal->("Docker build error: " . $event->{errorDetail}{message});
        }
        elsif (defined $event->{stream}) {
            for my $line ($self->_extract_build_lines(\$line_buf, $event->{stream}, $verbose)) {
                $self->logger->($line);
            }
        }
        elsif ($event->{progress}) {
            $self->logger->($event->{status} . ' ' . $event->{progress}) if $verbose;
        }
        if ($event->{aux} && $event->{aux}{ID}) {
            $image_id = $event->{aux}{ID};
        }
    };

    my $tarball;
    if (ref($context) eq 'HASH') {
        if ($context->{type} eq 'dir') {
            $tarball = $self->_create_tar($context->{path}, $context->{dockerfile});
        }
        elsif ($context->{type} eq 'archive') {
            $tarball = Path::Tiny::path($context->{path})->slurp_raw;
        }
        else {
            $self->logger_fatal->("Unknown context type: " . ($context->{type} // 'undef'));
        }
    }
    else {
        $tarball = $context;
    }

    eval {
        my $events = $docker->images->build(
            context => $tarball,
            %build_opts,
        );

        for my $event (@{$events // []}) {
            $progress_cb->($event);
        }
    };

    if (my $err = $@) {
        # API::Docker 0.003 croaks on the errorDetail event before the loop
        # above gets to run, so the output that led up to the failure rides
        # on the exception instead. Drain it from there, or a failed build
        # logs nothing but the last line (api-docker #12). The error event
        # itself is left out: the reason arrives through the fatal below.
        if (ref $err && $err->can('events')) {
            $progress_cb->($_) for grep { !$_->{errorDetail} } @{ $err->events };
        }
        $self->logger_fatal->("Docker build failed: $err");
    }

    for my $tag (@tags) {
        next if $tag eq ($tags[0] // '');
        my ( $repo, $tag_name ) = $self->_split_image_ref($tag);
        eval {
            $docker->images->tag($image_id,
                repo => $repo,
                defined $tag_name ? ( tag => $tag_name ) : (),
            );
        };
        if ($@) {
            $self->logger->("Warning: failed to tag image as $tag: $@");
            next;
        }
        push @processed_tags, $tag;
    }

    return Dist::Zilla::Plugin::Docker::API::Result->new(
        image_id => $image_id,
        tags     => \@processed_tags,
        pushed   => [],
    );
}

sub _extract_build_lines {
    my ($self, $buf_ref, $chunk, $verbose) = @_;
    $$buf_ref .= $chunk;
    my @out;
    while ($$buf_ref =~ s/^([^\n]*)\n//) {
        my $line = $1;
        next unless length $line;
        if ($verbose) {
            push @out, $line;
        }
        elsif ($self->_is_build_step_header($line)) {
            push @out, $line;
        }
    }
    return @out;
}

sub _is_build_step_header {
    my ($self, $line) = @_;
    return 0 unless defined $line && length $line;
    # Legacy builder: "Step 3/18 : RUN apt-get update"
    return 1 if $line =~ m{^Step \s+ \d+/\d+ \s* :}x;
    # Podman classic builder: "STEP 3/18: RUN apt-get update"
    return 1 if $line =~ m{^STEP \s+ \d+/\d+ \s* :}x;
    # BuildKit stage header: "#5 [4/12] RUN apt-get update"
    return 1 if $line =~ m{^\#\d+ \s+ \[\d+/\d+\]}x;
    # BuildKit named stage: "#7 [builder 3/8] COPY . ."
    return 1 if $line =~ m{^\#\d+ \s+ \[[^\]]+ \s+ \d+/\d+\]}x;
    return 0;
}

sub _create_tar {
    my ($self, $dir, $dockerfile) = @_;

    my $root = Path::Tiny::path($dir);
    my @entries = $self->_collect_files($root, $root);
    my @files;

    for my $entry (@entries) {
        my $name = $entry->relative($root)->stringify;
        next if $name =~ /^\./;
        push @files, $name => $entry->slurp_raw;
    }

    my $tar = Archive::Tar->new;
    for (my $i = 0; $i < @files; $i += 2) {
        $tar->add_data($files[$i], $files[$i+1]);
    }

    my $tarball;
    open my $fh, '>', \$tarball;
    $tar->write($fh, 1);
    close $fh;

    return \$tarball;
}

sub _collect_files {
    my ($self, $root, $dir) = @_;

    my @files;
    for my $entry ($dir->children) {
        if ($entry->is_dir) {
            push @files, $self->_collect_files($root, $entry);
        }
        else {
            push @files, $entry;
        }
    }
    return @files;
}

sub auth_for_image_ref {
    my ($self, $image_ref) = @_;
    my $registry = $self->_registry_for_image_ref($image_ref);
    return $self->_auth_for_registry($registry);
}

sub _registry_for_image_ref {
    my ($self, $image_ref) = @_;

    # Strip ":tag" or "@sha256:..." suffix from the image part.
    my $name = $image_ref;
    $name =~ s/\@sha256:.*$//;
    my @parts = split m{/}, $name;

    # If the first component does NOT look like a registry host
    # (no dot, no colon, not "localhost"), it's an implicit Docker Hub repo.
    if (@parts < 2 || ($parts[0] !~ /[.:]/ && $parts[0] ne 'localhost')) {
        return 'https://index.docker.io/v1/';
    }
    return $parts[0];
}

sub _auth_for_registry {
    my ($self, $registry) = @_;

    my $config = $self->_docker_config;
    my $auths = $config->{auths} // {};

    my @candidates = ($registry);
    if ($registry eq 'https://index.docker.io/v1/'
        || $registry eq 'index.docker.io'
        || $registry eq 'docker.io') {
        push @candidates,
            'https://index.docker.io/v1/',
            'https://index.docker.io/v2/',
            'index.docker.io',
            'docker.io';
    }

    my $entry;
    for my $key (@candidates) {
        if (exists $auths->{$key}) {
            $entry = $auths->{$key};
            last;
        }
    }
    return undef unless $entry;

    my %auth = (serveraddress => $registry);

    if ($entry->{identitytoken}) {
        $auth{identitytoken} = $entry->{identitytoken};
        return \%auth;
    }

    if ($entry->{auth}) {
        my $decoded = eval { decode_base64($entry->{auth}) };
        if (defined $decoded && $decoded =~ /^([^:]+):(.*)$/s) {
            $auth{username} = $1;
            $auth{password} = $2;
            return \%auth;
        }
    }

    if (defined $entry->{username} || defined $entry->{password}) {
        $auth{username} = $entry->{username} if defined $entry->{username};
        $auth{password} = $entry->{password} if defined $entry->{password};
        return \%auth;
    }

    return undef;
}

sub tag_image {
    my ($self, %arg) = @_;

    my $source = $arg{source};
    my $target = $arg{target};

    my ( $repo, $tag ) = $self->_split_image_ref($target);

    $self->docker->images->tag(
        $source,
        repo => $repo,
        defined $tag ? ( tag => $tag ) : (),
    );
}

sub push_image {
    my ($self, %arg) = @_;

    my $image_ref = $arg{image_ref};
    my $auth = exists $arg{auth} ? $arg{auth} : $self->auth_for_image_ref($image_ref);

    my $events;
    eval {
        $events = $self->docker->images->push($image_ref, auth => $auth);
    };

    if (my $err = $@) {
        # API::Docker 0.004 croaks on a push failure instead of handing back the
        # errorDetail event in the returned array (against Docker an
        # API::Docker::Error::Stream with ->events, on Podman it may be a plain
        # HTTP error). Pull the message off the stream event when it is there,
        # otherwise report the exception itself (api-docker #12).
        my $message = "$err";
        if (ref $err && $err->can('events')) {
            for my $event (@{ $err->events }) {
                next unless $event->{errorDetail};
                $message = $event->{errorDetail}{message};
                last;
            }
        }
        $self->logger_fatal->("Push error: " . $message);
    }

    # A success still returns the raw array; keep scanning it, defensively, in
    # case an engine reports a failure inside a 200 stream.
    for my $event (@{$events // []}) {
        if ($event->{errorDetail}) {
            $self->logger_fatal->("Push error: " . $event->{errorDetail}{message});
        }
    }
}

sub inspect_image {
    my ($self, $image_ref) = @_;

    return $self->docker->images->inspect($image_ref);
}

# Ask the *registry* whether a reference is already published, through the
# engine's GET /distribution/{name}/json. Credentials are optional: without
# any, the lookup is anonymous, which is what a public image needs.
#
# API::Docker's exists() croaks instead of answering "no" when the engine has
# no /distribution route -- rootless Podman has none, measured -- and that
# croak is deliberately not caught here. "This engine cannot answer" is not
# the same as "the tag is free", and only the caller can decide what to do
# about the difference.
sub remote_tag_exists {
    my ($self, $image_ref) = @_;

    my $auth = $self->auth_for_image_ref($image_ref);

    return $self->docker->distribution->exists(
        $image_ref,
        defined $auth ? ( auth => $auth ) : (),
    ) ? 1 : 0;
}

# Pre-flight for the release push: hand the engine, through POST /auth, the
# very credentials push_image would use for this reference and let the
# registry judge them. A rejected credential croaks; the caller is meant to
# make that fatal before anything is built.
#
# Returns undef when no credential could be resolved for the reference. That
# is not a failure -- an anonymous push to a public registry is a legal thing
# to do, and system->auth croaks on an empty AuthConfig, so there would be
# nothing to ask about.
sub verify_auth_for_image_ref {
    my ($self, $image_ref) = @_;

    my $auth = $self->auth_for_image_ref($image_ref);
    return undef unless $auth;

    return $self->docker->system->auth(auth => $auth);
}

1;