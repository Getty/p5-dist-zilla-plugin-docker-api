package Dist::Zilla::Plugin::Docker::API::TagTemplate;
# ABSTRACT: Template expansion for Docker image tags
our $VERSION = '0.002';
use Moo;

has zilla => (
    is       => 'ro',
    required => 1,
);

has plugin_name => (
    is       => 'ro',
    required => 1,
);

my %var_map = (
    n => 'name',
    v => 'version',
    t => 'trial',
    g => 'git_short_sha',
    G => 'git_full_sha',
    b => 'branch',
    d => 'build_root',
    o => 'source_root',
    a => 'archive',
    p => 'plugin_name',
    vmaj => 'version_major',
    vmin => 'version_minor',
);

my %known_var = map { $_ => 1 } keys %var_map;

sub expand {
    my ($self, $template, %vars) = @_;

    $template //= '';

    $template =~ s/%(\d+)/'%'.sprintf('%02d',$1)/eg;

    my $result = $template;
    $result =~ s/%([a-zA-Z][a-zA-Z0-9_]*)/_expand_var($1, %vars)/ge;

    return $result;
}

sub _extract_vars {
    my ($self, $template) = @_;
    my @vars;
    while ($template =~ /%([a-zA-Z][a-zA-Z0-9_]*)/g) {
        push @vars, $1 if $known_var{$1};
    }
    return @vars;
}

sub _expand_var {
    my ($var, %vars) = @_;

    my $key = $var_map{$var} // $var;
    my $value = $vars{$key} // '';

    # For version_major and version_minor, extract from version
    if ($var eq 'vmaj' || $var eq 'vmin') {
        my $version = $vars{version} // '';
        if ($version =~ /^(\d+)/) {
            $value = $1;
            if ($var eq 'vmin' && $version =~ /^\d+\.(\d+)/) {
                $value = $1;
            }
        }
    }

    return $value;
}

1;