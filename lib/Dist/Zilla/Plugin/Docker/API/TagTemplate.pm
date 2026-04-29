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
);

my %known_var = map { $_ => 1 } keys %var_map;

sub expand {
    my ($self, $template, %vars) = @_;

    $template //= '';

    $template =~ s/%(\d+)/'%'.sprintf('%02d',$1)/eg;

    my $result = $template;
    $result =~ s/%([a-zA-Z])/_expand_var($1, %vars)/ge;

    return $result;
}

sub _expand_var {
    my ($char, %vars) = @_;

    my $key = $var_map{$char} // $char;
    return $vars{$key} // '';
}

sub _extract_vars {
    my ($self, $template) = @_;
    my @vars;
    while ($template =~ /%([a-zA-Z])/g) {
        push @vars, $1 if $known_var{$1};
    }
    return @vars;
}

1;