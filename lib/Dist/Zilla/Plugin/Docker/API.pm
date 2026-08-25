package Dist::Zilla::Plugin::Docker::API;
# ABSTRACT: Build and publish Docker images as Dist::Zilla release artifacts
our $VERSION = '0.104';
use Moose;
with 'Dist::Zilla::Role::Plugin';
with 'Dist::Zilla::Role::BeforeBuild';
with 'Dist::Zilla::Role::AfterBuild';
with 'Dist::Zilla::Role::Releaser';

use namespace::autoclean;
use Log::Any qw($log);
use Path::Tiny;

use Dist::Zilla::Plugin::Docker::API::TagTemplate;
use Dist::Zilla::Plugin::Docker::API::Result;

# Primary attributes
has image => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    init_arg => 'image',
);

# Backward compatibility alias
has repository => (
    is       => 'ro',
    isa      => 'Str',
    lazy     => 1,
    default  => sub { shift->image },
);

has dockerfile => (
    is      => 'ro',
    isa     => 'Str',
    default => 'Dockerfile',
    init_arg => 'file',
);

# Canonical tag attribute: one list, applied both at build (locally) and
# at release (pushed). Deprecated build_tag / release_tag funnel into here
# via BUILDARGS.
has tag => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    lazy    => 1,
    builder => '_build_tag_default',
);

sub _build_tag_default { ['latest', '%V', '%v'] }

has build_arg => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
);

has label => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
);

has platform => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
);

# Build behavior
has build_load => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

# Deprecated alias
has load => (
    is      => 'ro',
    isa     => 'Bool',
    lazy    => 1,
    default => sub { shift->build_load },
);

# Release behavior
has release_push => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

# Deprecated alias
has push => (
    is      => 'ro',
    isa     => 'Bool',
    lazy    => 1,
    default => sub { shift->release_push },
);

has release_load => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

# When false (default), the build log only echoes Dockerfile step headers
# (e.g. "Step 3/18 : RUN apt-get update", Podman's "STEP 3/18: ..." or
# BuildKit's "#5 [4/12] ..."),
# not the per-command output. Set to true for the full stream.
has build_verbose => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has release_enabled => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

# Common options
has pull => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has no_cache => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has rm => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

has force_rm => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

has target => (
    is      => 'ro',
    isa     => 'Str',
    default => '',
    init_arg => '_target',
);

has network_mode => (
    is      => 'ro',
    isa     => 'Str',
    default => '',
    init_arg => '_network_mode',
);

has fail_if_tag_exists => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has skip_latest_on_trial => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

has client_class => (
    is      => 'ro',
    isa     => 'Str',
    default => 'Dist::Zilla::Plugin::Docker::API::Client',
);

has _tag_template => (
    is      => 'ro',
    isa     => 'Dist::Zilla::Plugin::Docker::API::TagTemplate',
    lazy    => 1,
    builder => '_build_tag_template',
);

has _client => (
    is      => 'ro',
    isa     => 'Object',
    lazy    => 1,
    builder => '_build_client',
);

sub _build_tag_template {
    my ($self) = @_;
    return Dist::Zilla::Plugin::Docker::API::TagTemplate->new(
        zilla     => $self->zilla,
        plugin_name => $self->plugin_name,
    );
}

sub _build_client {
    my ($self) = @_;
    my $client_class = $self->client_class;
    unless (eval "require $client_class; 1") {
        $self->log_fatal("Cannot load client_class $client_class: $@");
    }
    return $client_class->new(
        logger => sub { $self->log(@_) },
        logger_fatal => sub { $self->log_fatal(@_) },
    );
}

sub tag_template { shift->_tag_template }
sub client { shift->_client }

sub file { shift->dockerfile }

# after_build builds an image unconditionally, so every dzil command that
# builds needs a reachable engine. Ask for one up front instead of letting
# Dist::Zilla gather, munge and write out a whole distribution first and only
# then die on a socket that was never there.
sub before_build {
    my ($self) = @_;

    if ($ENV{DZIL_DOCKER_API_SKIP}) {
        $self->log('DZIL_DOCKER_API_SKIP is set: skipping the image build '
            .'for this run - no engine contact, no image');
        return;
    }

    return if $ENV{DZIL_DOCKER_API_SKIP_PRECHECK};

    my $info = eval { $self->client->engine_info };
    my $error = $@;

    if ($error) {
        # API::Docker croaks through Carp, so the reason arrives carrying one
        # or more " at FILE line N." tails. Strip all of them (not just the
        # last) and flatten to a single line -- log_fatal repeats whatever it
        # is given, and a multi-line message gets repeated in full.
        $error =~ s/\s+at\s+\S+\s+line\s+\d+\.?//g;
        $error =~ s/\s+/ /g;
        $error =~ s/^\s+|\s+$//g;

        $self->log('Docker::API speaks the Docker Engine HTTP API over a '
            .'socket and never shells out to the docker binary, so any engine '
            .'serving that API will do.');
        $self->log('Point DOCKER_HOST at one. For rootless Podman: '
            .'systemctl --user enable --now podman.socket, then '
            .'DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"');
        $self->log_fatal('cannot reach a container engine: '.$error
            .' (set DZIL_DOCKER_API_SKIP_PRECHECK=1 to skip this check)');
    }

    $self->log('Docker::API engine ready: '
        .($info->{engine} // 'unknown').' '
        .($info->{version} // '?')
        .' (API '.($info->{api_version} // '?').')');
}

sub after_build {
    my ($self, $arg) = @_;

    return if $ENV{DZIL_DOCKER_API_SKIP};

    $self->log("Docker::API building image");

    my $build_root = $arg->{build_root};
    my $zilla = $self->zilla;

    my %tmpl_vars = $self->_template_vars($build_root, undef, $arg->{archive});

    my @image_refs = $self->_resolve_tags($self->tag, %tmpl_vars);
    my %labels = $self->_resolve_labels(%tmpl_vars);
    my %build_args = $self->_resolve_build_args(%tmpl_vars);

    my $context_path = Path::Tiny->new($build_root // $self->zilla->root);
    unless ($context_path->child($self->dockerfile)->exists) {
        $self->log_fatal("Dockerfile '" . $self->dockerfile
            . "' not found in build context: $context_path");
    }
    my $context_tar = {
        type       => 'dir',
        path       => $context_path->stringify,
        dockerfile => $self->dockerfile,
    };

    my @platforms = @{ $self->platform };

    my $result = $self->client->build_image(
        context_tar  => $context_tar,
        dockerfile   => $self->dockerfile,
        tags         => \@image_refs,
        labels       => \%labels,
        buildargs    => \%build_args,
        pull         => $self->pull,
        nocache      => $self->no_cache,
        rm           => $self->rm,
        forcerm      => $self->force_rm,
        target       => $self->target,
        network_mode => $self->network_mode,
        platform     => $platforms[0],
        verbose      => $self->build_verbose,
    );

    $self->_log_build_result($result);
}

sub release {
    my ($self, $archive) = @_;

    # A skipped build phase means there is no image to tag and push. Refusing
    # here beats releasing a dist whose containers silently never shipped.
    $self->log_fatal('DZIL_DOCKER_API_SKIP is set: refusing to release '
        .'- the image build was skipped, there is nothing to push')
        if $ENV{DZIL_DOCKER_API_SKIP};

    # Skip if release is disabled
    return unless $self->release_enabled;

    # If no tags configured, skip
    return unless @{$self->tag};

    $self->log("Docker::API release: tagging and " . ($self->release_push ? "pushing" : "tagging only"));

    my $zilla = $self->zilla;
    my %tmpl_vars = $self->_template_vars($zilla->root, $zilla->version, $archive);

    my @tags = @{ $self->tag };

    if ($self->skip_latest_on_trial && $zilla->is_trial) {
        @tags = grep { $_ ne 'latest' } @tags;
        $self->log("Skipping 'latest' tag for trial release");
    }

    # Source image: first tag from the build phase (same list, resolved
    # via the same template). Build must have happened before release.
    my $source_image_ref = $self->image . ':' . $self->tag_template->expand($self->tag->[0], %tmpl_vars);

    # Check if tag exists on remote (if we're going to push)
    if ($self->release_push && $self->fail_if_tag_exists) {
        for my $tag (@tags) {
            my $image_ref = $self->_image_ref($tag, %tmpl_vars);
            if ($self->client->remote_tag_exists($image_ref)) {
                $self->log_fatal("Tag '$tag' already exists on remote registry");
            }
        }
    }

    # Tag existing image with release tags. If the source image is missing
    # (build never ran, or someone pruned the daemon), the underlying
    # Docker API will return a real 404 — surface that as a fatal error
    # instead of fabricating our own pre-check.
    my @image_refs = $self->_resolve_tags(\@tags, %tmpl_vars);
    for my $target_ref (@image_refs) {
        next if $target_ref eq $source_image_ref;
        eval {
            $self->client->tag_image(source => $source_image_ref, target => $target_ref);
        };
        if ($@) {
            $self->log_fatal("Failed to tag '$source_image_ref' as '$target_ref': $@");
        }
        $self->log("Tagged: $target_ref");
    }

    # Push if enabled
    if ($self->release_push) {
        my @failed;
        for my $image_ref (@image_refs) {
            $self->log("Pushing $image_ref...");
            eval {
                $self->client->push_image(image_ref => $image_ref);
            };
            if ($@) {
                $self->log("Warning: failed to push $image_ref: $@");
                push @failed, $image_ref;
            }
        }
        if (@failed) {
            $self->log_fatal("Push failed for: " . join(', ', @failed));
        }
    }
}

sub _template_vars {
    my ($self, $build_root, $version, $archive) = @_;
    my $zilla = $self->zilla;

    my $git = $self->_git_info;

    my %vars = (
        name          => $zilla->name,
        version       => $version // $zilla->version // '0',
        trial         => ($zilla->is_trial ? '-TRIAL' : ''),
        git_short_sha => $git->{short_sha} // '',
        git_full_sha  => $git->{full_sha} // '',
        branch        => $git->{branch} // '',
        build_root    => $build_root // '',
        source_root   => $zilla->root // '',
        archive       => $archive // '',
        plugin_name   => $self->plugin_name,
    );

    return %vars;
}

sub _git_info {
    my ($self) = @_;
    return $self->{_git_info} //= do {
        my $root   = $self->zilla->root;
        my $sha    = _git_capture($root, 'rev-parse', 'HEAD');
        my $branch = _git_capture($root, 'rev-parse', '--abbrev-ref', 'HEAD');

        my $full   = ($sha =~ /^([a-f0-9]{40})$/) ? $1 : '';
        my $br     = ($branch ne '' && $branch ne 'HEAD') ? $branch : '';

        {
            full_sha  => $full,
            short_sha => $full ? substr($full, 0, 7) : '',
            branch    => $br,
        };
    };
}

sub _git_capture {
    my ($dir, @cmd) = @_;
    my $pid = open(my $fh, '-|');
    return '' unless defined $pid;
    if ($pid == 0) {
        chdir $dir or exit 1;
        open STDERR, '>', '/dev/null';
        exec 'git', @cmd;
        exit 127;
    }
    my $out = do { local $/; <$fh> } // '';
    close $fh;
    return '' if $? != 0;
    chomp $out;
    return $out;
}

sub _resolve_tags {
    my ($self, $tags, %vars) = @_;
    return map { $self->_image_ref($_, %vars) } @{$tags};
}

sub _image_ref {
    my ($self, $tag, %vars) = @_;
    my $expanded = $self->tag_template->expand($tag, %vars);
    return $self->image . ':' . $expanded;
}

sub _resolve_labels {
    my ($self, %vars) = @_;
    my %labels;
    for my $label_def (@{ $self->label }) {
        if ($label_def =~ /^([^=]+)=(.*)$/) {
            my ($key, $value) = ($1, $2);
            $labels{$key} = $self->tag_template->expand($value, %vars);
        }
    }
    return %labels;
}

sub _resolve_build_args {
    my ($self, %vars) = @_;
    my %args;
    for my $arg_def (@{ $self->build_arg }) {
        if ($arg_def =~ /^([^=]+)=(.*)$/) {
            my ($key, $value) = ($1, $2);
            $args{$key} = $self->tag_template->expand($value, %vars);
        }
    }
    return %args;
}

sub _log_build_result {
    my ($self, $result) = @_;
    if ($result->image_id) {
        $self->log("Built image: " . $result->image_id);
    }
    if (@{ $result->tags }) {
        $self->log("Tagged: " . join(', ', @{ $result->tags }));
    }
    if (@{ $result->pushed }) {
        $self->log("Pushed: " . join(', ', @{ $result->pushed }));
    }
    if ($result->digest) {
        $self->log("Digest: " . $result->digest);
    }
    if (@{ $result->warnings }) {
        for my $warning (@{ $result->warnings }) {
            $self->log("Warning: $warning");
        }
    }
}

around BUILDARGS => sub {
    my ($orig, $class, @args) = @_;
    my $args = $class->$orig(@args);

    my @legacy = grep { exists $args->{$_} } qw(build_tag release_tag);
    if (@legacy) {
        warn "[Docker::API] '" . join("' and '", @legacy)
           . "' are deprecated; use 'tag' instead.\n"
           . "  They are merged into 'tag' for now and will be removed in a future release.\n";

        my @merged;
        push @merged, @{ delete $args->{build_tag} // [] };
        push @merged, @{ delete $args->{release_tag} // [] };

        if (exists $args->{tag}) {
            warn "[Docker::API] 'tag' is set explicitly; ignoring deprecated build_tag/release_tag values.\n";
        }
        else {
            my %seen;
            $args->{tag} = [ grep { !$seen{$_}++ } @merged ];
        }
    }

    return $args;
};

sub mvp_multivalue_args { qw(tag build_tag release_tag build_arg label platform) }

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 SYNOPSIS

    [Docker::API]
    image = ghcr.io/example/my-app

    tag = latest
    tag = %V
    tag = %v

    dockerfile = Dockerfile

    build_load   = 1
    release_push = 1

Or via the L<@Author::GETTY|Dist::Zilla::PluginBundle::Author::GETTY> bundle:

    [@Author::GETTY::Docker / runtime]
    image = ghcr.io/example/my-app
    tags  = latest %V %v

=head1 DESCRIPTION

This plugin builds and publishes Docker images as release artifacts derived from
the Dist::Zilla-built distribution.

=head1 BEHAVIOR

| Dzil command | Docker behavior |
|---|---|
| C<dzil build>   | Build image, apply every C<tag>, load into daemon (if C<build_load=1>), no push |
| C<dzil release> | Re-tag the built image with every C<tag>, push (if C<release_push=1>), load (if C<release_load=1>) |

The same C<tag> list is used in both phases — C<dzil build> produces local tags
for verification, C<dzil release> re-applies them (against the already-built
image) and pushes if configured.

=head1 CONTAINER ENGINE

Builds and pushes go through L<API::Docker>, which speaks the Docker Engine
HTTP API over a socket. No C<docker> binary is involved at any point, so any
engine serving that API will do, and Docker itself need not be installed.
Podman's rootless socket is a tested alternative:

    systemctl --user enable --now podman.socket
    export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"

C<target> reaches the engine unchanged, so the multi-stage builds this plugin
is usually pointed at behave the same either way.

The socket is located from C<DOCKER_HOST>, falling back to
C</var/run/docker.sock> and nothing else. Docker contexts are not consulted, so
a daemon selected with C<docker context use> will not be picked up here; set
C<DOCKER_HOST> in the environment C<dzil> runs in. See
L<API::Docker/CONTAINER ENGINES> for how that compares to other clients.

=head2 Startup precheck

Because C<after_build> builds an image unconditionally, every C<dzil> command
that builds needs a reachable engine. The plugin therefore asks the engine for
its version in C<before_build>, before Dist::Zilla gathers a single file, and
gives up there if nothing answers -- rather than letting a whole distribution
be assembled and only then dying on a socket that was never there.

On success the engine is named in the build log:

    [Docker::API] Docker::API engine ready: Podman Engine 5.4.2 (API 1.41)

Set C<DZIL_DOCKER_API_SKIP_PRECHECK=1> to skip the check and get the previous
behaviour back, where an unreachable engine only surfaces once the build
reaches the image. With several C<Docker::API> plugins in one F<dist.ini>,
each runs its own precheck.

Set C<DZIL_DOCKER_API_SKIP=1> to skip the image build entirely for one run --
no engine contact, no image, one loud log line per plugin. This is for local
C<dzil build> / C<dzil install> / C<dzil test> while the image cannot build
yet, for example while a dependency pinned in the F<Dockerfile>'s C<cpanm>
run is not released. C<dzil release> refuses to run with the variable set:
a skipped build phase means there is no image to tag and push.

=head1 CONFIGURATION

=over 4

=item C<image> - Full image repository (required). Example: C<ghcr.io/user/my-app>

=item C<tag> - Tags applied to the image (can be repeated, template-enabled).
Default: C<latest>, C<%V>, and C<%v> (e.g. C<latest>, C<0>, C<0.402>).
Applied identically in both build and release. Note: setting C<tag>
explicitly B<replaces> the default list, it does not append to it.

=item C<dockerfile> - Dockerfile name (default: C<Dockerfile>)

=item C<build_load> - Load built image into local Docker daemon (default: true)

=item C<release_push> - Push to registry during release (default: true)

=item C<release_load> - Load released image locally (default: false)

=item C<build_verbose> - When false (default), the build log only echoes
Dockerfile step headers — the legacy builder format C<Step N/M : ...>,
Podman's classic builder C<STEP N/M: ...> and BuildKit's C<#N [N/M] ...> —
instead of the full per-command output.
Set to true to see every line the daemon streams back. Errors are always
surfaced regardless of this flag.

=item C<fail_if_tag_exists> - Error if tag already exists on remote

=item C<skip_latest_on_trial> - Skip C<latest> tag for trial releases

=item C<build_arg> - Build arguments (can be repeated, template-enabled)

=item C<label> - OCI labels (can be repeated, template-enabled)

=item C<platform> - Target platform (can be repeated)

=back

=head1 DEPRECATED

The following names are still accepted but emit a warning and will be removed
in a future release:

=over 4

=item C<build_tag>, C<release_tag>

Replaced by the single C<tag> attribute. When either is given, the values are
merged (build_tag first, release_tag second) into C<tag> and a deprecation
warning is emitted. If C<tag> is also set explicitly, it wins and the legacy
values are ignored.

=item C<repository> - Use C<image> instead.

=item C<phase> - No longer needed; build and release phases are implicit.

=item C<push> - Use C<release_push> instead.

=item C<load> - Use C<build_load> instead.

=back

=head1 SEE ALSO

L<Dist::Zilla::Plugin::Docker::API::TagTemplate>,
L<Dist::Zilla::Plugin::Docker::API::Client>,
L<Dist::Zilla::Plugin::Docker::API::Result>