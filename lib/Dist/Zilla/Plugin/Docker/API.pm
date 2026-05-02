package Dist::Zilla::Plugin::Docker::API;
# ABSTRACT: Build and publish Docker images as Dist::Zilla release artifacts
our $VERSION = '0.004';
use Moose;
with 'Dist::Zilla::Role::Plugin';
with 'Dist::Zilla::Role::AfterBuild';
with 'Dist::Zilla::Role::Releaser';

use namespace::autoclean;
use Log::Any qw($log);

use Dist::Zilla::Plugin::Docker::API::Config;
use Dist::Zilla::Plugin::Docker::API::TagTemplate;
use Dist::Zilla::Plugin::Docker::API::Context;
use Dist::Zilla::Plugin::Docker::API::Client;
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

has _file => (
    is      => 'ro',
    isa     => 'Str',
    default => 'Dockerfile',
);

has context => (
    is      => 'ro',
    isa     => 'Str',
    default => 'build',
);

has build_tag => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { ['latest'] },
);

has release_tag => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { ['%v'] },
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
    init_arg => '_fail_if_tag_exists',
);

has skip_latest_on_trial => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
    init_arg => '_skip_latest_on_trial',
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
        repository           => $self->image,
        context              => $context_mode,
        file                 => $self->dockerfile,
        tags                 => $self->build_tag,  # default to build_tag, will be overridden per phase
        build_args           => $self->build_arg,
        labels               => $self->label,
        platforms            => $self->platform,
        push                 => $self->release_push,
        load                 => $self->build_load,
        pull                 => $self->pull,
        no_cache             => $self->no_cache,
        rm                   => $self->rm,
        force_rm             => $self->force_rm,
        target               => $self->target,
        network_mode         => $self->network_mode,
        fail_if_tag_exists   => $self->fail_if_tag_exists,
        skip_latest_on_trial => $self->skip_latest_on_trial,
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
    my $mode = $self->{context} // 'build';
    return Dist::Zilla::Plugin::Docker::API::Context->new(
        zilla    => $self->zilla,
        mode     => $mode,
        file     => $self->dockerfile,
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

sub file { shift->dockerfile }

sub after_build {
    my ($self, $arg) = @_;

    $self->log("Docker::API building image");

    my $build_root = $arg->{build_root};
    my $zilla = $self->zilla;

    my %tmpl_vars = $self->_template_vars($build_root, undef, $arg->{archive});

    my @image_refs = $self->_resolve_tags($self->build_tag, %tmpl_vars);
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

sub release {
    my ($self, $archive) = @_;

    # Skip if release is disabled
    return unless $self->release_enabled;

    # If no release tags configured, skip
    return unless @{$self->release_tag};

    $self->log("Docker::API release: tagging and " . ($self->release_push ? "pushing" : "tagging only"));

    my $zilla = $self->zilla;
    my %tmpl_vars = $self->_template_vars($zilla->root, $zilla->version, $archive);

    my @tags = @{ $self->release_tag };

    if ($self->skip_latest_on_trial && $zilla->is_trial) {
        @tags = grep { $_ ne 'latest' } @tags;
        $self->log("Skipping 'latest' tag for trial release");
    }

    # Get source image from first build_tag
    my $source_image_ref = $self->image . ':' . $self->tag_template->expand($self->build_tag->[0], %tmpl_vars);

    # Verify it exists locally
    unless ($self->client->image_exists_locally($source_image_ref)) {
        $self->log_fatal("Source image '$source_image_ref' not found locally. Run 'dzil build' first.");
    }

    # Check if tag exists on remote (if we're going to push)
    if ($self->release_push && $self->fail_if_tag_exists) {
        for my $tag (@tags) {
            my $image_ref = $self->_image_ref($tag, %tmpl_vars);
            if ($self->client->remote_tag_exists($image_ref)) {
                $self->log_fatal("Tag '$tag' already exists on remote registry");
            }
        }
    }

    # Tag existing image with release tags
    my @image_refs = $self->_resolve_tags(\@tags, %tmpl_vars);
    for my $target_ref (@image_refs) {
        eval {
            $self->client->tag_image(source => $source_image_ref, target => $target_ref);
            $self->log("Tagged: $target_ref");
        };
        if ($@) {
            $self->log("Warning: failed to tag as $target_ref: $@");
        }
    }

    # Push if enabled
    if ($self->release_push) {
        for my $image_ref (@image_refs) {
            $self->log("Pushing $image_ref...");
            eval {
                $self->client->push_image(image_ref => $image_ref);
            };
            if ($@) {
                $self->log("Warning: failed to push $image_ref: $@");
            }
        }
    }
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

sub mvp_multivalue_args { qw(build_tag release_tag build_arg label platform) }

1;

__END__

=head1 SYNOPSIS

    [Docker::API]
    image = ghcr.io/example/my-app

    build_tag = latest
    build_tag = test-%v

    release_tag = %v
    release_tag = latest

    dockerfile = Dockerfile
    context = archive

    build_load = 1
    release_push = 1

Or via pluginbundle:

    [@Author::GETTY]
    docker_image = ghcr.io/example/my-app
    docker_build = latest
    docker_release = %v

=head1 DESCRIPTION

This plugin builds and publishes Docker images as release artifacts derived from
the Dist::Zilla-built distribution.

=head1 BEHAVIOR

| Dzil command | Docker behavior |
|---|---|
| C<dzil build> | Build image, apply C<build_tag>, load into daemon (if C<build_load=1>), no push |
| C<dzil release> | Build image from release artifact, apply C<release_tag>, push (if C<release_push=1>), load (if C<release_load=1>) |

=head1 CONFIGURATION

=over 4

=item C<image> - Full image repository (required). Example: C<ghcr.io/user/my-app>

=item C<build_tag> - Tags applied during C<dzil build>. Default: C<latest>

=item C<release_tag> - Tags applied and pushed during C<dzil release>. Default: C<%v>

=item C<dockerfile> - Dockerfile name (default: C<Dockerfile>)

=item C<context> - Build context mode: C<build> (default), C<source>, or C<archive>

=item C<build_load> - Load built image into local Docker daemon (default: true)

=item C<release_push> - Push to registry during release (default: true)

=item C<release_load> - Load released image locally (default: false)

=item C<fail_if_tag_exists> - Error if tag already exists on remote

=item C<skip_latest_on_trial> - Skip 'latest' tag for trial releases

=item C<build_arg> - Build arguments (can be repeated, template-enabled)

=item C<label> - OCI labels (can be repeated, template-enabled)

=back

=head1 BACKWARD COMPATIBILITY

The following deprecated names are still supported but may be removed in a future release:

=over 4

=item C<repository> - Use C<image> instead

=item C<phase> - No longer needed; behavior is implicit based on dzil command

=item C<tag> - Use C<build_tag> or C<release_tag> instead

=item C<push> - Use C<release_push> instead

=item C<load> - Use C<build_load> instead

=back

=head1 SEE ALSO

L<Dist::Zilla::Plugin::Docker::API::Config>,
L<Dist::Zilla::Plugin::Docker::API::TagTemplate>,
L<Dist::Zilla::Plugin::Docker::API::Context>,
L<Dist::Zilla::Plugin::Docker::API::Client>,
L<Dist::Zilla::Plugin::Docker::API::Result>