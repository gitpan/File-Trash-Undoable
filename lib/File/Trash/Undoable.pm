package File::Trash::Undoable;

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';

use File::Trash::FreeDesktop;
use SHARYANTO::File::Util qw(l_abs_path);

our $VERSION = '0.10'; # VERSION

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
        suffix => {
            schema => 'str',
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
    my $dry_run   = $args{-dry_run};
    my $path      = $args{path};
    defined($path) or return [400, "Please specify path"];
    my $suffix    = $args{suffix};

    my @st     = lstat($path);
    my $exists = (-l _) || (-e _);

    my (@do, @undo);

    if (defined $suffix) {
        if ($tx_action eq 'check_state') {
            if ($exists) {
                unshift @undo, [untrash => {path=>$path, suffix=>$suffix}];
            }
            if (@undo) {
                $log->info("(DRY) Trashing $path ...") if $dry_run;
                return [200, "File/dir $path should be trashed",
                        undef, {undo_actions=>\@undo}];
            } else {
                return [304, "File/dir $path already does not exist"];
            }
        } elsif ($tx_action eq 'fix_state') {
            $log->info("Trashing $path ...");
            my $tfile;
            eval { $tfile = $trash->trash({suffix=>$suffix}, $path) };
            return $@ ? [500, "trash() failed: $@"] : [200, "OK", $tfile];
        }
        return [400, "Invalid -tx_action"];
    } else {
        my $taid = $args{-tx_action_id}
            or return [412, "Please specify -tx_action_id"];
        $suffix = substr($taid, 0, 8);
        if ($exists) {
            push    @do  , [trash   => {path=>$path, suffix=>$suffix}];
            unshift @undo, [untrash => {path=>$path, suffix=>$suffix}];
        }
        if (@undo) {
            $log->info("(DRY) Trashing $path (suffix $suffix) ...") if $dry_run;
            return [200, "", undef, {do_actions=>\@do, undo_actions=>\@undo}];
        } else {
            return [304, "File/dir $path already does not exist"];
        }
    }
}

$SPEC{untrash} = {
    v           => 1.1,
    summary     => 'Untrash a file',
    description => <<'_',

Fixed state: path exists.

Fixable state: Path does not exist (and exists in trash, and if suffix is
specified, has the same suffix).

_
    args        => {
        path => {
            schema => 'str*',
            req => 1,
        },
        suffix => {
            schema => 'str',
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
    my $dry_run   = $args{-dry_run};
    my $path0     = $args{path};
    defined($path0) or return [400, "Please specify path"];
    my $suffix    = $args{suffix};

    my $apath     = l_abs_path($path0);
    my @st        = lstat($apath);
    my $exists    = (-l _) || (-e _);

    if ($tx_action eq 'check_state') {

        my @undo;
        return [304, "Path $path0 already exists"] if $exists;

        my @res = $trash->list_contents({
            search_path=>$apath, suffix=>$suffix});
        return [412, "File/dir $path0 does not exist in trash"] unless @res;
        unshift @undo, [trash => {path => $apath, suffix=>$suffix}];
        $log->info("(DRY) Untrashing $path0 ...") if $dry_run;
        return [200, "File/dir $path0 should be untrashed",
                undef, {undo_actions=>\@undo}];

    } elsif ($tx_action eq 'fix_state') {
        $log->info("Untrashing $path0 ...");
        eval { $trash->recover({suffix=>$suffix}, $apath) };
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
    my $dry_run = $args{-dry_run};
    my $ff      = $args{files};
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
        $log->infof("(DRY) Trashing %s ...", $orig) if $dry_run;
        push    @do  , [trash   => {path=>$_}];
        unshift @undo, [untrash => {path=>$_, mtime=>$st[9]}];
    }

    return [200, "", undef, {do_actions=>\@do, undo_actions=>\@undo}];
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

version 0.10

=head1 SYNOPSIS

 # use the trash-u script

=head1 DESCRIPTION

This module provides routines to trash files, with undo/redo support. Actual
trashing/untrashing is provided by L<File::Trash::FreeDesktop>.

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

This software is copyright (c) 2013 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 FUNCTIONS


=head2 empty_trash() -> [status, msg, result, meta]

No arguments.

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head2 list_trash_contents() -> [status, msg, result, meta]

No arguments.

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head2 trash() -> [status, msg, result, meta]

No arguments.

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head2 trash_files() -> [status, msg, result, meta]

No arguments.

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head2 untrash() -> [status, msg, result, meta]

No arguments.

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=cut

