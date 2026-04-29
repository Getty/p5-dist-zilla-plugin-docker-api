requires 'Dist::Zilla::Role::Plugin';
requires 'Dist::Zilla::Role::AfterBuild';
requires 'Dist::Zilla::Role::BeforeRelease';
requires 'Dist::Zilla::Role::Releaser';
requires 'Dist::Zilla::Role::AfterRelease';
requires 'API::Docker';
requires 'Moo';
requires 'Types::Standard';
requires 'Path::Tiny';
requires 'Archive::Tar::Wrapper';
requires 'Log::Any';

on test => sub {
    requires 'Test::More';
    requires 'Test::DZil';
    requires 'Path::Tiny';
    requires 'File::Temp';
    requires 'Capture::Tiny';
};

on develop => sub {
    requires 'Dist::Zilla';
    requires 'Perl::Critic';
    requires 'Test::Pod';
};