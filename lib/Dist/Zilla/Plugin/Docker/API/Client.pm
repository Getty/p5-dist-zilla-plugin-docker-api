package Dist::Zilla::Plugin::Docker::API::Client;
# ABSTRACT: Thin adapter around API::Docker
our $VERSION = '0.004';
use Moo;
use Path::Tiny;

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
    my $push = $arg{push} // 0;

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

    my $image_id;
    my @processed_tags;

    my $progress_cb = sub {
        my ($event) = @_;
        if ($event->{errorDetail}) {
            $self->logger_fatal->("Docker build error: " . $event->{errorDetail}{message});
        }
        elsif ($event->{stream}) {
            $self->logger->($event->{stream});
        }
        elsif ($event->{progress}) {
            $self->logger->($event->{status} . ' ' . $event->{progress});
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

    if ($@) {
        $self->logger_fatal->("Docker build failed: $@");
    }

    for my $tag (@tags) {
        next if $tag eq ($tags[0] // '');
        eval {
            $docker->images->tag(image => $image_id, repo => $tag);
        };
        if ($@) {
            $self->logger->("Warning: failed to tag image as $tag: $@");
        }
        push @processed_tags, $tag;
    }

    my $result = Dist::Zilla::Plugin::Docker::API::Result->new(
        image_id => $image_id,
        tags     => \@processed_tags,
        pushed   => [],
    );

    if ($push && @tags) {
        $self->_push_tags($docker, \@tags, \$result);
    }

    return $result;
}

sub _create_tar {
    my ($self, $dir, $dockerfile) = @_;

    eval { require Archive::Tar; };
    if ($@) {
        $self->logger_fatal->("Archive::Tar required for creating tar context: $@");
    }

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

sub _push_tags {
    my ($self, $docker, $tags, $result_ref) = @_;

    for my $tag (@$tags) {
        $self->logger->("Pushing $tag...");

        my $push_progress = sub {
            my ($event) = @_;
            if ($event->{errorDetail}) {
                $self->logger_fatal->("Push error for $tag: " . $event->{errorDetail}{message});
            }
            elsif ($event->{progress}) {
                $self->logger->($event->{status} . ' ' . $event->{progress});
            }
        };

        eval {
            my $events = $docker->images->push(image => $tag);
            for my $event (@{$events // []}) {
                $push_progress->($event);
                if ($event->{aux} && $event->{aux}{Digest}) {
                    $$result_ref->{digest} = $event->{aux}{Digest};
                }
            }
        };

        if ($@) {
            $self->logger->("Warning: failed to push $tag: $@");
        }
        else {
            push @{ $$result_ref->{pushed} }, $tag;
        }
    }
}

sub tag_image {
    my ($self, %arg) = @_;

    my $source = $arg{source};
    my $target = $arg{target};

    $self->docker->images->tag(
        image => $source,
        repo  => $target,
    );
}

sub push_image {
    my ($self, %arg) = @_;

    my $image_ref = $arg{image_ref};
    my $auth = $arg{auth};

    my $events = $self->docker->images->push(image => $image_ref);
    for my $event (@{$events // []}) {
        if ($event->{errorDetail}) {
            $self->logger_fatal->("Push error: " . $event->{errorDetail}{message});
        }
    }
}

sub inspect_image {
    my ($self, $image_ref) = @_;

    return $self->docker->images->inspect(image => $image_ref);
}

sub image_exists_locally {
    my ($self, $image_ref) = @_;

    eval {
        $self->docker->images->inspect(image => $image_ref);
    };
    return $@ ? 0 : 1;
}

sub remote_tag_exists {
    my ($self, $image_ref) = @_;

    return 0;
}

1;