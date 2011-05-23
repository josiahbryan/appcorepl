#!/usr/bin/perl

use strict;

use lib '/var/www/html/appcore/lib';
use AppCore::DBI;
use AppCore::Common;

use AppCore::EmailQueue;

AppCore::EmailQueue->send_all;