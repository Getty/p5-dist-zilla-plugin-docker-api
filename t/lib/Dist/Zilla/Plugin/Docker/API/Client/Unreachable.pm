package Dist::Zilla::Plugin::Docker::API::Client::Unreachable;
# ABSTRACT: Recording fake whose engine cannot be reached, for precheck tests
use Moo;
use Carp qw( croak );

extends 'Dist::Zilla::Plugin::Docker::API::Client::Recorder';

sub engine_info {
    my ( $self ) = @_;
    $self->_record('engine_info');
    croak 'connect: No such file or directory';
}

1;
