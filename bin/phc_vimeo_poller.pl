#!/usr/bin/perl

use lib '/var/www/html/appcore/lib';
use AppCore::Web::Module;
use ThemePHC::Videos;
use AppCore::Common;
use strict;

# Make sure we're only running one polling instance at a time
use Fcntl qw(:flock);
flock(DATA, LOCK_EX|LOCK_NB) or die "Already running";

system("date >> /tmp/phc_vimeo_poller.crontab");

print date().": $0 Starting...\n";

my $controller = ThemePHC::Videos->new;
$controller->sync_from_vimeo();
$controller->sync_from_ustream();

print date().": $0 Finished\n\n";


__DATA__
# Data section exists for the purpose of locking

