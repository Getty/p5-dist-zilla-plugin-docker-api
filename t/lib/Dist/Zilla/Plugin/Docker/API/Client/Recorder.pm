package Dist::Zilla::Plugin::Docker::API::Client::Recorder;
# ABSTRACT: Recording fake of the Docker::API::Client seam for tests
use Moo;
use Carp qw( croak );

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

# What the registry says about a tag: 0 = free, 1 = already published.
has remote_tag_exists_result => (
    is      => 'rw',
    default => sub { 0 },
);

# Set to a message to make remote_tag_exists croak instead of answering --
# the engine-has-no-/distribution-route case (rootless Podman).
has remote_tag_exists_error => (
    is      => 'rw',
    default => sub { undef },
);

# What verify_auth_for_image_ref returns. undef (the default) means no
# credential could be resolved for the reference, which is not an error.
has verify_auth_result => (
    is      => 'rw',
    default => sub { undef },
);

# Set to a message to make verify_auth_for_image_ref croak -- the registry
# rejecting the credentials.
has verify_auth_error => (
    is      => 'rw',
    default => sub { undef },
);

sub _record {
    my ($self, $name, %args) = @_;
    push @{ $self->calls }, { method => $name, %args };
}

sub engine_info {
    my ($self) = @_;
    $self->_record('engine_info');
    return {
        version     => '0.0-fake',
        api_version => '1.41',
        engine      => 'Recorder Engine',
    };
}

sub build_image {
    my ($self, %arg) = @_;
    $self->_record('build_image', %arg);

    my @tags = @{ $arg{tags} // [] };

    return Dist::Zilla::Plugin::Docker::API::Result->new(
        image_id => $self->image_id_to_return,
        tags     => [ @tags ],
        pushed   => [],
    );
}

sub tag_image {
    my ($self, %arg) = @_;
    $self->_record('tag_image', %arg);
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

sub remote_tag_exists {
    my ($self, $image_ref) = @_;
    $self->_record('remote_tag_exists', image_ref => $image_ref);
    croak $self->remote_tag_exists_error if defined $self->remote_tag_exists_error;
    return $self->remote_tag_exists_result;
}

sub verify_auth_for_image_ref {
    my ($self, $image_ref) = @_;
    $self->_record('verify_auth_for_image_ref', image_ref => $image_ref);
    croak $self->verify_auth_error if defined $self->verify_auth_error;
    return $self->verify_auth_result;
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
