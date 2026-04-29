package Dist::Zilla::Plugin::Docker::API;
# ABSTRACT: Build and publish Docker images as Dist::Zilla release artifacts

use Moose;
with 'Dist::Zilla::Role::Plugin';
with 'Dist::Zilla::Role::AfterBuild';
with 'Dist::Zilla::Role::BeforeRelease';
with 'Dist::Zilla::Role::Releaser';
with 'Dist::Zilla::Role::AfterRelease';

use namespace::autoclean;
use Log::Any qw($log);

use Dist::Zilla::Plugin::Docker::API::Config;
use Dist::Zilla::Plugin::Docker::API::TagTemplate;
use Dist::Zilla::Plugin::Docker::API::Context;
use Dist::Zilla::Plugin::Docker::API::Client;
use Dist::Zilla::Plugin::Docker::API::Result;

has _phase => (
    is      => 'ro',
    isa     => 'Str',
    default => 'build',
);

has repository => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has _file => (
    is      => 'ro',
    isa     => 'Str',
    default => 'Dockerfile',
);

has tag => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { ['latest'] },
);

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

has push => (
    is      => 'ro',
    isa     => 'Bool',
    default => sub { $_[0]->_phase eq 'release' },
);

has load => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

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

has _target => (
    is      => 'ro',
    isa     => 'Str',
    default => '',
);

has _network_mode => (
    is      => 'ro',
    isa     => 'Str',
    default => '',
);

has _fail_if_tag_exists => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has _skip_latest_on_trial => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

has _allow_dirty => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has client_class => (
    is      => 'ro',
    isa     => 'Str',
    default => 'Dist::Zilla::Plugin::Docker::API::Client',
);

has _config => (
    is      => 'ro',
    isa     => 'Dist::Zilla::Plugin::Docker::API::Config',
    lazy    => 1,
    builder => '_build_config',
);

has _tag_template => (
    is      => 'ro',
    isa     => 'Dist::Zilla::Plugin::Docker::API::TagTemplate',
    lazy    => 1,
    builder => '_build_tag_template',
);

has _context => (
    is      => 'ro',
    isa     => 'Dist::Zilla::Plugin::Docker::API::Context',
    lazy    => 1,
    builder => '_build_context',
);

has _client => (
    is      => 'ro',
    isa     => 'Dist::Zilla::Plugin::Docker::API::Client',
    lazy    => 1,
    builder => '_build_client',
);

sub _build_config {
    my ($self) = @_;
    my $ctx = $self->_context;
    my $context_mode = ref($ctx) eq 'Dist::Zilla::Plugin::Docker::API::Context' ? $ctx->mode : $ctx;
    return Dist::Zilla::Plugin::Docker::API::Config->new(
        repository           => $self->repository,
        phase                => $self->_phase,
        context              => $context_mode,
        file                 => $self->_file,
        tags                 => $self->tag,
        build_args           => $self->build_arg,
        labels               => $self->label,
        platforms            => $self->platform,
        push                 => $self->push,
        load                 => $self->load,
        pull                 => $self->pull,
        no_cache             => $self->no_cache,
        rm                   => $self->rm,
        force_rm             => $self->force_rm,
        target               => $self->_target,
        network_mode         => $self->_network_mode,
        fail_if_tag_exists   => $self->_fail_if_tag_exists,
        skip_latest_on_trial => $self->_skip_latest_on_trial,
        allow_dirty          => $self->_allow_dirty,
    );
}

sub _build_tag_template {
    my ($self) = @_;
    return Dist::Zilla::Plugin::Docker::API::TagTemplate->new(
        zilla     => $self->zilla,
        plugin_name => $self->plugin_name,
    );
}

sub _build_context {
    my ($self) = @_;
    my $mode = $self->{_context} // ($self->_phase eq 'release' ? 'archive' : 'build');
    return Dist::Zilla::Plugin::Docker::API::Context->new(
        zilla    => $self->zilla,
        mode     => $mode,
        file     => $self->_file,
    );
}

sub _build_client {
    my ($self) = @_;
    my $client_class = $self->client_class;
    return $client_class->new(
        logger => sub { $self->log(@_) },
        logger_fatal => sub { $self->log_fatal(@_) },
    );
}

sub config { shift->_config }
sub tag_template { shift->_tag_template }
sub context_resolver { shift->_context }
sub client { shift->_client }

sub phase { shift->_phase }
sub context { shift->_context }
sub file { shift->_file }

sub _context_mode { shift->_context }

sub after_build {
    my ($self, $arg) = @_;
    return unless $self->phase eq 'build';

    $self->log("Docker::API phase=build starting");

    my $build_root = $arg->{build_root};
    my $zilla = $self->zilla;

    my %tmpl_vars = $self->_template_vars($build_root, undef, $arg->{archive});

    my @image_refs = $self->_resolve_tags(%tmpl_vars);
    my %labels = $self->_resolve_labels(%tmpl_vars);
    my %build_args = $self->_resolve_build_args(%tmpl_vars);

    my $context_tar = $self->context_resolver->resolve(
        build_root => $build_root,
        archive => undef,
    );

    my $result = $self->client->build_image(
        context_tar => $context_tar,
        dockerfile  => $self->config->file,
        tags        => \@image_refs,
        labels      => \%labels,
        buildargs   => \%build_args,
        pull        => $self->config->pull,
        nocache     => $self->config->no_cache,
        rm          => $self->config->rm,
        forcerm     => $self->config->force_rm,
    );

    $self->_log_build_result($result);
}

sub before_release {
    my ($self, $archive) = @_;
    return unless $self->phase eq 'release';

    $self->log("Docker::API phase=release preflight");

    my $zilla = $self->zilla;
    my %tmpl_vars = $self->_template_vars($zilla->root, $zilla->version, $archive);

    my @tags = @{ $self->config->tags };

    if ($self->config->skip_latest_on_trial && $zilla->is_trial) {
        @tags = grep { $_ ne 'latest' } @tags;
        $self->log("Skipping 'latest' tag for trial release");
    }

    if ($self->config->fail_if_tag_exists) {
        for my $tag (@tags) {
            my $image_ref = $self->_image_ref($tag, %tmpl_vars);
            if ($self->client->remote_tag_exists($image_ref)) {
                $self->log_fatal("Tag '$tag' already exists on remote registry");
            }
        }
    }

    $self->log("Preflight complete, ready for release");
}

sub release {
    my ($self, $archive) = @_;
    return unless $self->phase eq 'release';

    $self->log("Docker::API phase=release building and pushing");

    my $zilla = $self->zilla;
    my %tmpl_vars = $self->_template_vars($zilla->root, $zilla->version, $archive);

    my @tags = @{ $self->config->tags };

    if ($self->config->skip_latest_on_trial && $zilla->is_trial) {
        @tags = grep { $_ ne 'latest' } @tags;
    }

    my @image_refs = $self->_resolve_tags(%tmpl_vars, tags => \@tags);
    my %labels = $self->_resolve_labels(%tmpl_vars);
    my %build_args = $self->_resolve_build_args(%tmpl_vars);

    my $context_tar = $self->context_resolver->resolve(
        build_root => undef,
        archive => $archive,
    );

    my $result = $self->client->build_image(
        context_tar => $context_tar,
        dockerfile  => $self->config->file,
        tags        => \@image_refs,
        labels      => \%labels,
        buildargs   => \%build_args,
        pull        => $self->config->pull,
        nocache     => $self->config->no_cache,
        rm          => $self->config->rm,
        forcerm     => $self->config->force_rm,
        push        => $self->config->push,
    );

    $self->_log_build_result($result);

    if ($self->config->push && $result->digest) {
        $self->log("Digest: " . $result->digest);
    }
}

sub after_release {
    my ($self, $archive) = @_;
    return unless $self->phase eq 'release';

    $self->log("Docker::API phase=release complete");
}

sub _template_vars {
    my ($self, $build_root, $version, $archive) = @_;
    my $zilla = $self->zilla;

    my $git = $self->_git_info;

    my %vars = (
        n => $zilla->name,
        v => $version // $zilla->version // '0',
        t => ($zilla->is_trial ? '-TRIAL' : ''),
        g => $git->{short_sha} // '',
        G => $git->{full_sha} // '',
        b => $git->{branch} // '',
        d => $build_root // '',
        o => $zilla->root // '',
        a => $archive // '',
        p => $self->plugin_name,
    );

    return %vars;
}

sub _git_info {
    my ($self) = @_;
    return $self->{_git_info} //= do {
        eval {
            my $git_dir = $self->zilla->root;
            my $head = Path::Tiny->path($git_dir, '.git', 'HEAD')->slurp_utf8;
            chomp($head);
            my $branch = '';
            if ($head =~ /^ref: refs\/heads\/(.+)$/) {
                $branch = $1;
            }
            my ($short_sha, $full_sha) = ('', '');
            if (my $ref_file = Path::Tiny->path($git_dir, '.git', 'HEAD')->realpath) {
                if ($ref_file->is_file && $ref_file->lines_count <= 1) {
                    my $ref = $ref_file->slurp_utf8;
                    chomp($ref);
                    if ($ref =~ m{^([a-f0-9]{40})$}) {
                        $full_sha = $1;
                        $short_sha = substr($full_sha, 0, 7);
                    }
                }
            }
            { branch => $branch, short_sha => $short_sha, full_sha => $full_sha };
        } // {};
    };
}

sub _resolve_tags {
    my ($self, %vars) = @_;
    my @tags = @{ $self->config->tags };
    return map { $self->_image_ref($_, %vars) } @tags;
}

sub _image_ref {
    my ($self, $tag, %vars) = @_;
    my $expanded = $self->tag_template->expand($tag, %vars);
    return $self->config->repository . ':' . $expanded;
}

sub _resolve_labels {
    my ($self, %vars) = @_;
    my %labels;
    for my $label_def (@{ $self->config->labels }) {
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
    for my $arg_def (@{ $self->config->build_args }) {
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

__PACKAGE__->meta->make_immutable;

sub mvp_multivalue_args { qw(tag build_arg label platform) }

1;

__END__

=head1 SYNOPSIS

    [Docker::API]
    phase      = build
    repository = ghcr.io/example/my-app
    context    = build
    file       = Dockerfile

    tag = latest
    tag = build-%v

    push = 0
    load = 1

Or for release:

    [Docker::API / release]
    phase      = release
    repository = ghcr.io/example/my-app
    context    = archive

    tag = %v
    tag = v%v
    tag = latest

    push = 1
    fail_if_tag_exists = 1
    skip_latest_on_trial = 1

=head1 DESCRIPTION

This plugin builds and publishes Docker images as release artifacts derived from
the Dist::Zilla-built distribution. The Docker image is built from the files that
Dist::Zilla generated, including munged modules, generated Makefile.PL/Build.PL,
generated META files, and injected files.

=head1 ROLE REQUIREMENTS

This plugin consumes the following roles:

=over 4

=item L<Dist::Zilla::Role::Plugin>

=item L<Dist::Zilla::Role::AfterBuild>

=item L<Dist::Zilla::Role::BeforeRelease>

=item L<Dist::Zilla::Role::Releaser>

=item L<Dist::Zilla::Role::AfterRelease>

=back

=head1 CONFIGURATION

=over 4

=item C<phase> - When to run. C<build> (default), C<release>, or C<after_release>

=item C<repository> - Full image repository (required)

=item C<context> - Build context mode: C<build> (default), C<source>, or C<archive>

=item C<file> - Dockerfile name (default: C<Dockerfile>)

=item C<tag> - Image tags (can be repeated). Templates: C<%n>, C<%v>, C<%g>, etc.

=item C<push> - Push to registry (default: true for release, false for build)

=item C<load> - Load into local Docker daemon (default: true)

=item C<fail_if_tag_exists> - Error if tag already exists on remote

=item C<skip_latest_on_trial> - Skip 'latest' tag for trial releases

=item C<build_arg> - Build arguments (can be repeated, template-enabled)

=item C<label> - OCI labels (can be repeated, template-enabled)

=back

=head1 SEE ALSO

L<Dist::Zilla::Plugin::Docker::API::Config>,
L<Dist::Zilla::Plugin::Docker::API::TagTemplate>,
L<Dist::Zilla::Plugin::Docker::API::Context>,
L<Dist::Zilla::Plugin::Docker::API::Client>,
L<Dist::Zilla::Plugin::Docker::API::Result>