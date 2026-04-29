use strict;
use warnings;
use Test::More;
use Dist::Zilla::Plugin::Docker::API::Config;

subtest 'basic config' => sub {
    my $config = Dist::Zilla::Plugin::Docker::API::Config->new(
        repository => 'ghcr.io/example/my-app',
    );

    is($config->repository, 'ghcr.io/example/my-app');
    is($config->phase, 'build');
    is($config->context, 'build');
    is($config->file, 'Dockerfile');
    is_deeply($config->tags, ['latest']);
    is_deeply($config->build_args, []);
    is_deeply($config->labels, []);
    is($config->push, 0);
    is($config->load, 1);
};

subtest 'full config' => sub {
    my $config = Dist::Zilla::Plugin::Docker::API::Config->new(
        repository           => 'ghcr.io/example/my-app',
        phase                => 'release',
        context              => 'archive',
        file                 => 'Dockerfile.multistage',
        tags                 => ['%v', 'latest'],
        build_args           => ['DIST_NAME=%n'],
        labels               => ['org.opencontainers.image.title=%n'],
        platforms            => ['linux/amd64'],
        push                 => 1,
        load                 => 0,
        pull                 => 1,
        no_cache             => 1,
        rm                   => 1,
        force_rm             => 1,
        target               => 'build',
        network_mode         => 'host',
        fail_if_tag_exists   => 1,
        skip_latest_on_trial => 1,
        allow_dirty          => 0,
    );

    is($config->phase, 'release');
    is($config->context, 'archive');
    is($config->file, 'Dockerfile.multistage');
    is_deeply($config->tags, ['%v', 'latest']);
    is_deeply($config->build_args, ['DIST_NAME=%n']);
    is_deeply($config->labels, ['org.opencontainers.image.title=%n']);
    is_deeply($config->platforms, ['linux/amd64']);
    is($config->push, 1);
    is($config->load, 0);
    is($config->pull, 1);
    is($config->no_cache, 1);
    is($config->target, 'build');
    is($config->network_mode, 'host');
    is($config->fail_if_tag_exists, 1);
    is($config->skip_latest_on_trial, 1);
};

subtest 'defaults for release phase' => sub {
    my $config = Dist::Zilla::Plugin::Docker::API::Config->new(
        repository => 'ghcr.io/example/my-app',
        phase      => 'release',
    );

    is($config->phase, 'release');
    is($config->context, 'build');
    is($config->push, 0);
    is($config->load, 1);
};

done_testing;