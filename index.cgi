#!/usr/bin/perl
#
# Script: index.cgi
#
use strict;
use CGI qw/:standard Vars/;

use lib 'lib';
use AppCore::Web::DispatchCore;

my $dispatch = AppCore::Web::DispatchCore->new();
my $q = CGI->new();
$dipatch->process($q);
