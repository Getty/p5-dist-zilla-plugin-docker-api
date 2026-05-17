package Dist::Zilla::Plugin::Docker::API::Client::Recorder;
# ABSTRACT: Recording fake of the Docker::API::Client seam for tests
use Moo;

use Dist::Zilla::Plugin::Docker::API::Result;

has logger       => (is => 'ro', required => 1);
has logger_fatal => (is => 'ro', required => 1);

has calls => (
    is      => 'ro',
    default => sub { [] },
);

# Canned responses (override per test):
has image_id_to_return => (
    is      => 'rw',
    default => sub { 'sha256:deadbeef' },
);

has locally_present => (
    is      => 'rw',
    default => sub { {} },     # image_ref => 1
);

sub _record {
    my ($self, $name, %args) = @_;
    push @{ $self->calls }, { method => $name, %args };
}

sub build_image {
    my ($self, %arg) = @_;
    $self->_record('build_image', %arg);

    my @tags = @{ $arg{tags} // [] };
    $self->locally_present->{$_} = 1 for @tags;

    return Dist::Zilla::Plugin::Docker::API::Result->new(
        image_id => $self->image_id_to_return,
        tags     => [ @tags ],
        pushed   => [],
    );
}

sub tag_image {
    my ($self, %arg) = @_;
    $self->_record('tag_image', %arg);
    $self->locally_present->{ $arg{target} } = 1 if $arg{target};
    return 1;
}

sub push_image {
    my ($self, %arg) = @_;
    $self->_record('push_image', %arg);
    return 1;
}

sub inspect_image {
    my ($self, $image_ref) = @_;
    $self->_record('inspect_image', image_ref => $image_ref);
    return { Id => $self->image_id_to_return };
}

sub image_exists_locally {
    my ($self, $image_ref) = @_;
    $self->_record('image_exists_locally', image_ref => $image_ref);
    return $self->locally_present->{$image_ref} ? 1 : 0;
}

sub remote_tag_exists {
    my ($self, $image_ref) = @_;
    $self->_record('remote_tag_exists', image_ref => $image_ref);
    return 0;
}

sub calls_of {
    my ($self, $method) = @_;
    return [ grep { $_->{method} eq $method } @{ $self->calls } ];
}

sub reset_calls {
    my ($self) = @_;
    @{ $self->calls } = ();
}

1;
