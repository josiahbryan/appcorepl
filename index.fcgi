#!/usr/bin/perl
#
# Script: index.fcgi
#

use strict;
use CGI::Fast qw/:standard Vars/;

use lib 'lib';
use AppCore::Web::DispatchCore;

my $dispatch = AppCore::Web::DispatchCore->new();

while(my $q = CGI::Fast->new)
{
	$dispatch->process($q);
}
