package File::Trash::Undoable;

use 5.010;
use strict;
use warnings;

use Cwd qw(abs_path);
use File::Trash::FreeDesktop;
use Perinci::Sub::Gen::Undoable 0.13 qw(gen_undoable_func);

our $VERSION = '0.01'; # VERSION

our %SPEC;

my $trash = File::Trash::FreeDesktop->new;

my $res = gen_undoable_func(
    name => 'trash_files',
    summary => 'Trash files (with undo support)',
    args => {
        files => {
            summary => 'Files/dirs to delete',
            schema => ['array*' => {of=>'str*'}],
            req => 1,
            pos => 0,
            greedy => 1,
        },
    },
    check_args => sub {
        my $args = shift;
        $args->{files} or return [400, "Please specify files"];
        ref($args->{files}) eq 'ARRAY' or return [400, "Files must be array"];
        # necessary?
        @{$args->{files}} > 0 or return [400, "Please specify at least 1 file"];
        [200, "OK"];
    },
    build_steps => sub {
        my $args = shift;
        my $ff   = $args->{files};

        my @steps;
        for (@$ff) {
            my $a = abs_path($_);
            return [500, "Can't find $_"] unless $a;
            push @steps, ["trash", $a];
        }
        [200, "OK", \@steps];
    },
    steps => {
        trash => {
            summary => 'Trash a file',
            description => <<'_',

Argument is path (should be absolute).

_
            check => sub {
                my ($args, $step) = @_;
                return [200, "OK", ["recover", $step->[1]]];
            },
            fix => sub {
                my ($args, $step, $undo) = @_;
                my $a = $step->[1];
                $trash->trash($a);
                [200, "OK"];
            },
        },
        recover => {
            summary => 'Recover a file',
            description => <<'_',

Argument is path.

_
            check => sub {
                my ($args, $step) = @_;
                return [200, "OK", ["trash", $step->[1]]];
            },
            fix => sub {
                my ($args, $step, $undo) = @_;
                my $a = $step->[1];
                $trash->recover($a);
                [200, "OK"];
            },
        },
    },
);
$res->[0] == 200 or die "Can't generate function: $res->[0] - $res->[1]";

$SPEC{list_trash_contents} = {
    summary => 'List contents of trash directory',
};
sub list_trash_contents {
    my %args = @_;
    [200, "OK", [$trash->list_contents]];
}

$SPEC{empty_trash} = {
    summary => 'List contents of trash directory',
};
sub empty_trash {
    my %args = @_;
    my $cmd  = $args{-cmdline};

    $trash->empty;
    $cmd->run_clear_history;
    $cmd->{_res};
}

1;
# ABSTRACT: Trash files (with undo support)


__END__
=pod

=head1 NAME

File::Trash::Undoable - Trash files (with undo support)

=head1 VERSION

version 0.01

=head1 SYNOPSIS

 # use the u-trash, u-trash-empty script

=head1 DESCRIPTION

This module provides routines to trash files, with undo/redo support. Originally
written to demonstrate/test L<Perinci::Sub::Gen::Undoable>.

=head1 SEE ALSO

=over 4

=item * B<gvfs-trash>

A command-line utility, part of the GNOME project.

=item * B<trash-cli>, https://github.com/andreafrancia/trash-cli

A Python-based command-line application. Also follows freedesktop.org trash
specification.

=item * B<rmv>, http://code.google.com/p/rmv/

A bash script. Features undo ("rollback"). At the time of this writing, does not
support per-filesystem trash (everything goes into home trash).

=back

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

