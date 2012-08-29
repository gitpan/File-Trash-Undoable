
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "File::Path" => "2.07",
    "File::Slurp" => 0,
    "File::chdir" => 0,
    "Module::Build" => "0.3601",
    "Test::More" => "0.96",
    "Test::Perinci::Tx::Manager" => 0,
    "autodie" => 0
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Trash files (with undo support)",
  "dist_author" => [
    "Steven Haryanto <stevenharyanto\@gmail.com>"
  ],
  "dist_name" => "File-Trash-Undoable",
  "dist_version" => "0.07",
  "license" => "perl",
  "module_name" => "File::Trash::Undoable",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "File::Trash::FreeDesktop" => "0.08",
    "Log::Any" => 0,
    "Perinci::CmdLine" => "0.58",
    "Perinci::Tx::Manager" => "0.30",
    "Rinci" => "v1.1.26",
    "SHARYANTO::File::Util" => "0.26",
    "UUID::Random" => 0,
    "perl" => "5.010000"
  },
  "script_files" => [
    "bin/trash-u"
  ]
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
