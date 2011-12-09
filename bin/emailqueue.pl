#!/usr/bin/perl

use strict;

use lib '/var/www/html/appcore/lib';
use AppCore::DBI;
use AppCore::Common;

use AppCore::EmailQueue;

# Make sure we're only running one polling instance at a time
use Fcntl qw(:flock);
flock(DATA, LOCK_EX|LOCK_NB) or die "Already running";

AppCore::EmailQueue->send_all;

__DATA__
# Data section exists for the purpose of locking
