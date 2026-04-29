package Dist::Zilla::Plugin::Docker::API::Context;
# ABSTRACT: Build context resolver for Docker image builds
our $VERSION = '0.002';
use Moo;
use Types::Standard qw(Str InstanceOf);
use Path::Tiny;

has zilla => (
    is       => 'ro',
    required => 1,
);

has mode => (
    is      => 'ro',
    isa     => Str,
    default => 'build',
);

has file => (
    is      => 'ro',
    default => 'Dockerfile',
);

sub resolve {
    my ($self, %arg) = @_;

    my $build_root = $arg{build_root};
    my $archive = $arg{archive};

    if ($self->mode eq 'build') {
        return $self->_context_build($build_root);
    }
    elsif ($self->mode eq 'source') {
        return $self->_context_source;
    }
    elsif ($self->mode eq 'archive') {
        return $self->_context_archive($archive);
    }
    else {
        die "Unknown context mode: " . $self->mode;
    }
}

sub _context_build {
    my ($self, $build_root) = @_;

    my $root = Path::Tiny->new($build_root // $self->zilla->root);

    my $dockerfile_path = $root->child($self->file);
    unless ($dockerfile_path->exists) {
        die "Dockerfile '" . $self->file . "' not found in build context: " . $root->stringify;
    }

    return {
        type => 'dir',
        path => $root->stringify,
        dockerfile => $self->file,
    };
}

sub _context_source {
    my ($self) = @_;

    my $root = Path::Tiny->new($self->zilla->root);

    my $dockerfile_path = $root->child($self->file);
    unless ($dockerfile_path->exists) {
        die "Dockerfile '" . $self->file . "' not found in source root";
    }

    return {
        type => 'dir',
        path => $root->stringify,
        dockerfile => $self->file,
    };
}

sub _context_archive {
    my ($self, $archive) = @_;

    die "Archive path required for context=archive"
        unless $archive && -f $archive;

    return {
        type => 'archive',
        path => $archive,
        dockerfile => $self->file,
    };
}

1;