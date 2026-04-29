package Dist::Zilla::Plugin::Docker::API::Result;
# ABSTRACT: Result object from Docker image build/push operations

use Moo;
use Types::Standard qw(Str ArrayRef);

has image_id => (
    is  => 'ro',
    isa => Str,
);

has tags => (
    is      => 'ro',
    isa     => ArrayRef [Str],
    default => sub { [] },
);

has pushed => (
    is      => 'ro',
    isa     => ArrayRef [Str],
    default => sub { [] },
);

has digest => (
    is  => 'ro',
    isa => Str,
);

has warnings => (
    is      => 'ro',
    isa     => ArrayRef [Str],
    default => sub { [] },
);

1;