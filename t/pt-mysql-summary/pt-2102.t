#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use PerconaTest;
use Sandbox;
use DSNParser;
require VersionParser;
use Test::More;
use File::Temp qw( tempdir );

local $ENV{PTDEBUG} = "";

my $dp         = new DSNParser(opts=>$dsn_opts);
my $sb         = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $has_keyring_plugin;

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 3;
}

my $db_flavor = VersionParser->new($master_dbh)->flavor();
if ( $db_flavor =~ m/Percona Server/ ) {
    my $rows = $master_dbh->selectall_hashref("SHOW PLUGINS", "name");
    while (my ($key, $values) = each %$rows) {
        if ($key =~ m/^keyring_/) {
            $has_keyring_plugin=1;
            last;
        }
    }
}

# mysqldump from earlier versions doesn't seem to work with 5.6,
# so use the actual mysqldump from each MySQL bin which should
# always be compatible with itself.
# We need LC_NUMERIC=POSIX, so test does not fail in environment 
# which use , insead of . for numbers.
my $env = qq\CMD_MYSQLDUMP="$ENV{PERCONA_TOOLKIT_SANDBOX}/bin/mysqldump" LC_NUMERIC=POSIX\;

#
# --save-samples
#

my $dir = tempdir( "percona-testXXXXXXXX", CLEANUP => 1 );

my $output;
my $cnf = '/tmp/12345/my.sandbox.cnf';
diag(`cp $cnf $cnf.bak`);
my $cmd = "$trunk/bin/pt-mysql-summary --sleep 1 -- --defaults-file=$cnf";

diag(`echo "[mysqld]" > /tmp/12345/my.sandbox.2.cnf`);
diag(`echo "wait_timeout=12345" >> /tmp/12345/my.sandbox.2.cnf`);
diag(`echo "!include /tmp/12345/my.sandbox.2.cnf" >> $cnf`);

$output = `$cmd`;

like(
   $output,
   qr/wait_timeout\s+=\s+12345/s,
   "!include works"
);

diag(`cp $cnf.bak $cnf`);

diag(`mkdir -p /tmp/12345/my.sandbox.3`);
diag(`echo "[mysqld]" > /tmp/12345/my.sandbox.3/my.sandbox.cnf`);
diag(`echo "wait_timeout=23456" >> /tmp/12345/my.sandbox.3/my.sandbox.cnf`);
diag(`echo "!includedir /tmp/12345/my.sandbox.3" >> $cnf`);

$output = `$cmd`;

like(
   $output,
   qr/wait_timeout\s+=\s+23456/s,
   "!includedir works"
);

diag(`cp $cnf.bak $cnf`);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;
