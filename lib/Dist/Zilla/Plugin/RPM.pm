package Dist::Zilla::Plugin::RPM;
# ABSTRACT: Build an RPM from your Dist::Zilla release

use Moose;
use Moose::Autobox;
use Moose::Util::TypeConstraints qw(enum);
use namespace::autoclean;

# VERSION

with 'Dist::Zilla::Role::Releaser',
     'Dist::Zilla::Role::FilePruner';

has spec_file => (
    is      => 'ro',
    isa     => 'Str',
    default => 'build/dist.spec',
);

has build => (
    is      => 'ro',
    isa     => enum([qw/source all/]),
    default => 'all',
);

has sign => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has ignore_build_deps => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has define => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub{[]},
);

sub mvp_multivalue_args { return qw(define); }

use Carp;
use File::Temp ();
use Path::Class qw(dir);
use Text::Template ();

sub prune_files {
    my($self) = @_;
    my $spec = $self->spec_file;
    for my $file ($self->zilla->files->flatten) {
        if ($file->name eq $self->spec_file) {
            $self->zilla->prune_file($file);
        }
    }
    return;
}

sub release {
    my($self,$archive) = @_;

    my $tmpdir  = File::Temp->newdir();
    my $tmpfile = dir($tmpdir)->file($self->zilla->name . '.spec');
    my $tmp = $tmpfile->openw();
    $tmp->print($self->mk_spec($archive));
    $tmp->flush;

    my @defineargs = ();
    foreach ( @{$self->define} ) {
        next if !$_;
        push @defineargs, '--define', "'$_'";
    }
    my $definestr = join(' ', @defineargs);

    my $sourcedir = qx/rpm $definestr --eval '%{_sourcedir}'/
        or $self->log_fatal(q{couldn't determine RPM sourcedir});
    $sourcedir =~ s/[\r\n]+$//;
    $sourcedir .= '/';
    system('cp',$archive,$sourcedir)
        && $self->log_fatal('cp failed');

    my @cmd = qw/rpmbuild/;
    if ($self->build eq 'source') {
        push @cmd, qw/-bs/;
    } elsif ($self->build eq 'all') {
        push @cmd, qw/-ba/;
    } else {
        $self->log_fatal(q{invalid build type }.$self->build);
    }
    push @cmd, @defineargs;
    push @cmd, qw/--sign/   if $self->sign;
    push @cmd, qw/--nodeps/ if $self->ignore_build_deps;
    push @cmd, "$tmpfile";

    if ($ENV{DZIL_PLUGIN_RPM_TEST}) {
        $self->log("test: would have executed @cmd");
    } else {
        system("@cmd") && $self->log_fatal('rpmbuild failed');
    }

    return;
}

sub mk_spec {
    my($self,$archive) = @_;
    my $t = Text::Template->new(
        TYPE       => 'FILE',
        SOURCE     => $self->zilla->root->file($self->spec_file),
        DELIMITERS => [ '<%', '%>' ],
    ) || $self->log_fatal($Text::Template::ERROR);
    return $t->fill_in(
        HASH => {
            zilla   => \($self->zilla),
            archive => \$archive,
        },
    ) || $self->log_fatal($Text::Template::ERROR);
}

__PACKAGE__->meta->make_immutable;

=head1 SYNOPSIS

In your dist.ini:

    [RPM]
    spec_file = build/dist.spec
    sign = 1
    ignore_build_deps = 0
    
=head1 DESCRIPTION

This plugin is a Releaser for Dist::Zilla that builds an RPM of your
distribution.

=head1 ATTRIBUTES

=over

=item spec_file (default: "build/dist.spec")

The spec file to use to build the RPM.

The spec file is run through L<Text::Template|Text::Template> before calling
rpmbuild, so you can substitute values from Dist::Zilla into the final output.
The template uses <% %> tags (like L<Mason|Mason>) as delimiters to avoid
conflict with standard spec file markup.

Two variables are available in the template:

=over

=item $zilla

The main Dist::Zilla object

=item $archive

The filename of the release tarball

=back

=item sign (default: False)

If set to a true value, rpmbuild will be called with the --sign option.

=back

=item ignore_build_deps (default: False)

If set to a true value, rpmbuild will be called with the --nodeps option.

=back

=head1 SAMPLE SPEC FILE TEMPLATE

    Name: <% $zilla->name %>
    Version: <% (my $v = $zilla->version) =~ s/^v//; $v %>
    Release: 1

    Summary: <% $zilla->abstract %>
    License: GPL+ or Artistic
    Group: Applications/CPAN
    BuildArch: noarch
    URL: <% $zilla->license->url %>
    Vendor: <% $zilla->license->holder %>
    Source: <% $archive %>
    
    BuildRoot: %{_tmppath}/%{name}-%{version}-BUILD
    
    %description
    <% $zilla->abstract %>
    
    %prep
    %setup -q
    
    %build
    perl Makefile.PL
    make test
    
    %install
    if [ "%{buildroot}" != "/" ] ; then
        rm -rf %{buildroot}
    fi
    make install DESTDIR=%{buildroot}
    find %{buildroot} | sed -e 's#%{buildroot}##' > %{_tmppath}/filelist
    
    %clean
    if [ "%{buildroot}" != "/" ] ; then
        rm -rf %{buildroot}
    fi
    
    %files -f %{_tmppath}/filelist
    %defattr(-,root,root)

=head1 SEE ALSO

L<Dist::Zilla|Dist::Zilla>

=cut

1;
