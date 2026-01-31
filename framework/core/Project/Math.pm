#-------------------------------------------------------------------------------
# Copyright (c) 2014-2024 René Just, Darioush Jalali, and Defects4J contributors.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#-------------------------------------------------------------------------------

=pod

=head1 NAME

Project::Math.pm -- L<Project> submodule for Commons-math.

=head1 DESCRIPTION

This module provides all project-specific configurations and subroutines for the
Commons-math project.

=cut
package Project::Math;

use strict;
use warnings;

use Constants;
use Vcs::Git;

our @ISA = qw(Project);
my $PID  = "Math";

sub new {
    @_ == 1 or die $ARG_ERROR;
    my ($class) = @_;

    my $name = "commons-math";
    my $vcs  = Vcs::Git->new($PID,
                             "$REPO_DIR/$name.git",
                             "$PROJECTS_DIR/$PID/$BUGS_CSV_ACTIVE",
                             \&_post_checkout);

    return $class->SUPER::new($PID, $name, $vcs);
}

#
# Determines the directory layout for sources and tests
#
sub determine_layout {
    @_ == 2 or die $ARG_ERROR;
    my ($self, $rev_id) = @_;
    my $dir = $self->{prog_root};
    my $result = _layout1($dir) // _layout2($dir);
    die "Unknown layout for revision: ${rev_id}" unless defined $result;
    return $result;
}

#
# Existing Ant build.xml and default.properties
#
sub _layout1 {
    @_ == 1 or die $ARG_ERROR;
    my ($dir) = @_;
    my $src  = `grep 'name="source.home"' $dir/build.xml 2>/dev/null`; chomp $src;
    my $test = `grep 'name="test.home"' $dir/build.xml 2>/dev/null`; chomp $test;

    return undef if ($src eq "" || $test eq "");

    $src =~ s/.*"source\.home"\s*value\s*=\s*"(\S+)".*/$1/;
    $test=~ s/.*"test\.home"\s*value\s*=\s*"(\S+)".*/$1/;

    return {src=>$src, test=>$test};
}

#
# Generated build.xml (from mvn ant:ant) with maven-build.properties
#
sub _layout2 {
    @_ == 1 or die $ARG_ERROR;
    my ($dir) = @_;
    my $src  = `grep "<sourceDirectory>" $dir/project.xml 2>/dev/null`; chomp $src;
    my $test = `grep "<unitTestSourceDirectory>" $dir/project.xml 2>/dev/null`; chomp $test;

    return undef if ($src eq "" || $test eq "");

    $src =~ s/.*<sourceDirectory>\s*([^<]+)\s*<\/sourceDirectory>.*/$1/;
    $test=~ s/.*<unitTestSourceDirectory>\s*([^<]+)\s*<\/unitTestSourceDirectory>.*/$1/;

    return {src=>$src, test=>$test};
}

sub _post_checkout {
    my ($self, $revision_id, $work_dir) = @_;

    # Set source, target version, and ISO-8859-1 encoding in javac targets.
    # This fixes encoding issues with files containing non-ASCII characters
    # (e.g., HermiteInterpolator.java, StorelessBivariateCovariance.java, etc.)
    # The original source files are encoded in ISO-8859-1, not UTF-8.
    my $jvm_version="1.6";

    if (-e "$work_dir/build.xml") {
        rename("$work_dir/build.xml", "$work_dir/build.xml.bak");
        open(IN, "<$work_dir/build.xml.bak") or die $!;
        open(OUT, ">$work_dir/build.xml") or die $!;
        
        # Track if we're inside a <javac> element (may span multiple lines)
        my $in_javac = 0;
        my $javac_has_encoding = 0;
        
        while(<IN>) {
            my $l = $_;
            
            # Old-style build.xml (uses deprecation="true") - add target and source version
            $l =~ s/(javac destdir="\$\{classesdir\}" deprecation="true")/$1 target="${jvm_version}" source="${jvm_version}"/g;
            $l =~ s/(javac destdir="\$\{testclassesdir\}" deprecation="true")/$1 target="${jvm_version}" source="${jvm_version}"/g;
            
            # Change source.encoding property from UTF-8 to ISO-8859-1
            # This ensures all javac tasks using ${source.encoding} get the correct encoding
            $l =~ s/(<property\s+name="source\.encoding"\s+value=")UTF-8(".*\/>)/$1ISO-8859-1$2/g;
            
            # Track javac elements to handle multi-line encoding attributes
            if ($l =~ /<javac\s/) {
                $in_javac = 1;
                $javac_has_encoding = ($l =~ /encoding=/) ? 1 : 0;
            }
            if ($in_javac && $l =~ /encoding=/) {
                $javac_has_encoding = 1;
            }
            if ($in_javac && $l =~ />/) {
                # End of javac opening tag - add encoding if not present
                if (!$javac_has_encoding && $l =~ />/) {
                    $l =~ s/>/ encoding="ISO-8859-1">/;
                }
                $in_javac = 0 if $l !~ /<javac/; # Only reset if this isn't the same line as <javac
            }
            
            $l =~ s/value="1\.[1-5]"/value="${jvm_version}"/g;

            print OUT $l;
        }
        close(IN);
        close(OUT);
    }
}

#
# Remove looping tests in addition to the broken ones
#
sub fix_tests {
    @_ == 2 or die $ARG_ERROR;
    my ($self, $vid) = @_;
    Utils::check_vid($vid);

    $self->SUPER::fix_tests($vid);

    my $dir = $self->test_dir($vid);

    # TODO: Check whether these tests should be excluded on a per-version basis
    my $file = "$PROJECTS_DIR/$PID/broken_tests";
    if (-e $file) {
        $self->exclude_tests_in_file($file, $dir);
    }
}

1;
