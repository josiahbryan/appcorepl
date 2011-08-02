#!/usr/bin/perl
#
# Script: index.fcgi
#

use strict;
use CGI::Fast qw/:standard Vars/;

use lib 'lib';
use AppCore::Web::DispatchCore;

my $dispatch = AppCore::Web::DispatchCore->new();

my $last_mod = undef;

AppCore::DBI->prime_cached_dbobjects;

while(my $q = CGI::Fast->new)
{
	$ENV{HTTP_HOST} = $ENV{HTTP_X_FORWARDED_HOST} if $ENV{HTTP_X_FORWARDED_HOST};
	
	REPROCESS_MODTIME:
	my $mod = undef;
	eval
	{
		$mod = AppCore::DBI->db_modtime;
	};
	if($@ =~ /MySQL server has gone away/)
	{
		AppCore::DBI->clear_handle_cache;
		AppCore::DBI->setup_modtime_sth;
		goto REPROCESS_MODTIME;
	}
	
	if($last_mod && $mod > $last_mod)
	{
		#print STDERR "Database updated, clearing cached object index... ($mod > $last_mod)\n";
		AppCore::DBI->clear_cached_dbobjects;
	}
	else
	{
		#print STDERR "No DB Change ($mod < $last_mod)\n";
	}
	$last_mod = $mod;
	#print STDERR "index.fcgi: modtime: $last_mod\n";
	$dispatch->process($q);
}
