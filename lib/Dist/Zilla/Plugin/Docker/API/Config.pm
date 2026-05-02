package Dist::Zilla::Plugin::Docker::API::Config;
# ABSTRACT: Normalized immutable configuration object for Docker::API plugin
our $VERSION = '0.004';
use Moo;
use Types::Standard qw(Str ArrayRef Bool);

has repository => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has phase => (
    is      => 'ro',
    isa     => Str,
    default => 'build',
);

has context => (
    is      => 'ro',
    isa     => Str,
    default => 'build',
);

has file => (
    is      => 'ro',
    isa     => Str,
    default => 'Dockerfile',
);

has tags => (
    is      => 'ro',
    isa     => ArrayRef [Str],
    default => sub { ['latest'] },
);

has build_args => (
    is      => 'ro',
    isa     => ArrayRef [Str],
    default => sub { [] },
);

has labels => (
    is      => 'ro',
    isa     => ArrayRef [Str],
    default => sub { [] },
);

has platforms => (
    is      => 'ro',
    isa     => ArrayRef [Str],
    default => sub { [] },
);

has push => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has load => (
    is      => 'ro',
    isa     => Bool,
    default => 1,
);

has pull => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has no_cache => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has rm => (
    is      => 'ro',
    isa     => Bool,
    default => 1,
);

has force_rm => (
    is      => 'ro',
    isa     => Bool,
    default => 1,
);

has target => (
    is      => 'ro',
    isa     => Str,
    default => '',
);

has network_mode => (
    is      => 'ro',
    isa     => Str,
    default => '',
);

has fail_if_tag_exists => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has skip_latest_on_trial => (
    is      => 'ro',
    isa     => Bool,
    default => 1,
);

has allow_dirty => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has registry_auth_stash => (
    is      => 'ro',
    isa     => Str,
    default => '',
);

has client_class => (
    is      => 'ro',
    isa     => Str,
    default => 'API::Docker',
);

1;