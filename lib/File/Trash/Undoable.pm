package File::Trash::Undoable;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use SHARYANTO::File::Util qw(l_abs_path);
use File::Trash::FreeDesktop;

our $VERSION = '0.06'; # VERSION

our %SPEC;

my $trash = File::Trash::FreeDesktop->new;

$SPEC{trash} = {
    v           => 1.1,
    name        => 'trash',
    summary     => 'Trash a file',
    args        => {
        path => {
            schema => 'str*',
            req => 1,
        },
    },
    description => <<'_',

Fixed state: path does not exist.

Fixable state: path exists.

_
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub trash {
    my %args = @_;

    # TMP, SCHEMA
    my $tx_action = $args{-tx_action} // "";
    my $path = $args{path};
    defined($path) or return [400, "Please specify path"];

    my @st     = lstat($path);
    my $exists = (-l _) || (-e _);

    my @undo;

    if ($tx_action eq 'check_state') {
        if ($exists) {
            push @undo, [untrash => {path=>$path, mtime=>$st[9]}];
        }
        if (@undo) {
            return [200, "Fixable", undef, {undo_actions=>\@undo}];
        } else {
            return [304, "Fixed"];
        }
    } elsif ($tx_action eq 'fix_state') {
        $log->info("Trashing $path ...");
        eval { $trash->trash($path) };
        return $@ ? [500, "trash() failed: $@"] : [200, "OK"];
    }
    [400, "Invalid -tx_action"];
}

$SPEC{untrash} = {
    v           => 1.1,
    summary     => 'Untrash a file',
    description => <<'_',

Fixed state: path exists (and if mtime is specified, with same mtime).

Fixable state: Path does not exist (and exists in trash, and if mtime is
specified, has the exact same mtime).

_
    args        => {
        path => {
            schema => 'str*',
            req => 1,
        },
        mtime => {
            schema => 'int*',
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub untrash {
    my %args = @_;

    # TMP, SCHEMA
    my $tx_action = $args{-tx_action} // "";
    my $path0 = $args{path};
    defined($path0) or return [400, "Please specify path"];
    my $mtime = $args{mtime};

    my $apath  = l_abs_path($path0);
    my @st     = lstat($apath);
    my $exists = (-l _) || (-e _);

    if ($tx_action eq 'check_state') {

        my @undo;
        if ($exists) {
            if (defined $mtime) {
                if ($st[9] == $mtime) {
                    return [304, "Path exists (with same mtime)"];
                } else {
                    return [412, "Path exists (with different mtime)"];
                }
            } else {
                return [304, "Path exists"];
            }
        }

        my @res = $trash->list_contents({
            search_path=>$apath, mtime=>$args{mtime}});
        return [412, "Path does not exist in trash"] unless @res;
        push @undo, [trash => {path => $apath}];
        return [200, "Fixable", undef, {undo_actions=>\@undo}];

    } elsif ($tx_action eq 'fix_state') {
        $log->info("Untrashing $path0 ...");
        eval { $trash->recover($apath) };
        return $@ ? [500, "untrash() failed: $@"] : [200, "OK"];
    }
    [400, "Invalid -tx_action"];
}

$SPEC{trash_files} = {
    v          => 1.1,
    summary    => 'Trash files (with undo support)',
    args       => {
        files => {
            summary => 'Files/dirs to delete',
            description => <<'_',

Files must exist.

_
            schema => ['array*' => {of=>'str*'}],
            req => 1,
            pos => 0,
            greedy => 1,
        },
    },
    features => {
        tx => {v=>2},
        idempotent => 1,
    },
};
sub trash_files {
    my %args = @_;

    # TMP, SCHEMA
    my $ff   = $args{files};
    $ff or return [400, "Please specify files"];
    ref($ff) eq 'ARRAY' or return [400, "Files must be array"];
    @$ff > 0 or return [400, "Please specify at least 1 file"];

    my (@do, @undo);
    for (@$ff) {
        my @st = lstat($_) or return [400, "Can't stat $_: $!"];
        (-l _) || (-e _) or return [400, "File does not exist: $_"];
        my $orig = $_;
        $_ = l_abs_path($_);
        $_ or return [400, "Can't convert to absolute path: $orig"];
        push @do  , [trash   => {path=>$_}];
        push @undo, [untrash => {path=>$_, mtime=>$st[9]}];
    }

    return [200, "Fixable", undef, {do_actions=>\@do, undo_actions=>\@undo}];
}

$SPEC{list_trash_contents} = {
    summary => 'List contents of trash directory',
};
sub list_trash_contents {
    my %args = @_;
    [200, "OK", [$trash->list_contents]];
}

$SPEC{empty_trash} = {
    summary => 'Empty trash',
};
sub empty_trash {
    my %args = @_;
    my $cmd  = $args{-cmdline};

    $trash->empty;
    if ($cmd) {
        $cmd->run_clear_history;
        return $cmd->{_res};
    } else {
        [200, "OK"];
    }
}

1;
# ABSTRACT: Trash files (with undo support)


__END__
=pod

=head1 NAME

File::Trash::Undoable - Trash files (with undo support)

=head1 VERSION

version 0.06

=head1 SYNOPSIS

 # use the trash-u script

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

=head1 DESCRIPTION


This module has L<Rinci> metadata.

=head1 FUNCTIONS


None are exported by default, but they are exportable.

=head2 empty_trash() -> [status, msg, result, meta]

Empty trash.

No arguments.

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head2 list_trash_contents() -> [status, msg, result, meta]

List contents of trash directory.

No arguments.

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head2 trash(%args) -> [status, msg, result, meta]

Trash a file.

Fixed state: path does not exist.

Fixable state: path exists.

This function is idempotent (repeated invocations with same arguments has the same effect as single invocation).


Arguments ('*' denotes required arguments):

=over 4

=item * B<path>* => I<str>

=back

Special arguments:

=over 4

=item * B<-tx_action> => I<str>

You currently can set this to 'rollback'. Usually you do not have to pass this yourself, L<Perinci::Access::InProcess> will do it for you. For more details on transactions, see L<Rinci::function::Transaction>.

=item * B<-tx_manager> => I<obj>

Instance of transaction manager object, usually L<Perinci::Tx::Manager>. Usually you do not have to pass this yourself, L<Perinci::Access::InProcess> will do it for you. For more details on transactions, see L<Rinci::function::Transaction>.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head2 trash_files(%args) -> [status, msg, result, meta]

Trash files (with undo support).

This function is idempotent (repeated invocations with same arguments has the same effect as single invocation).


Arguments ('*' denotes required arguments):

=over 4

=item * B<files>* => I<array>

Files/dirs to delete.

Files must exist.

=back

Special arguments:

=over 4

=item * B<-tx_action> => I<str>

You currently can set this to 'rollback'. Usually you do not have to pass this yourself, L<Perinci::Access::InProcess> will do it for you. For more details on transactions, see L<Rinci::function::Transaction>.

=item * B<-tx_manager> => I<obj>

Instance of transaction manager object, usually L<Perinci::Tx::Manager>. Usually you do not have to pass this yourself, L<Perinci::Access::InProcess> will do it for you. For more details on transactions, see L<Rinci::function::Transaction>.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head2 untrash(%args) -> [status, msg, result, meta]

Untrash a file.

Fixed state: path exists (and if mtime is specified, with same mtime).

Fixable state: Path does not exist (and exists in trash, and if mtime is
specified, has the exact same mtime).

This function is idempotent (repeated invocations with same arguments has the same effect as single invocation).


Arguments ('*' denotes required arguments):

=over 4

=item * B<mtime> => I<int>

=item * B<path>* => I<str>

=back

Special arguments:

=over 4

=item * B<-tx_action> => I<str>

You currently can set this to 'rollback'. Usually you do not have to pass this yourself, L<Perinci::Access::InProcess> will do it for you. For more details on transactions, see L<Rinci::function::Transaction>.

=item * B<-tx_manager> => I<obj>

Instance of transaction manager object, usually L<Perinci::Tx::Manager>. Usually you do not have to pass this yourself, L<Perinci::Access::InProcess> will do it for you. For more details on transactions, see L<Rinci::function::Transaction>.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

