#!/usr/bin/perl
#
# Script: index.fcgi
#

use strict;
use CGI::Fast qw/:standard Vars/;

use lib 'lib';
use AppCore::Web::DispatchCore;

my $dispatch = AppCore::Web::DispatchCore->new();

my $db_modtime_sth; 
sub setup_modtime_sth
{
	$db_modtime_sth = AppCore::DBI->dbh('information_schema')->prepare("select sum(UPDATE_TIME) as checksum from TABLES where TABLE_TYPE = 'BASE TABLE' and TABLE_SCHEMA!='mysql'");
}
setup_modtime_sth();

my $last_mod = undef;

while(my $q = CGI::Fast->new)
{
	REPROCESS_MODTIME:
	eval
	{
		$db_modtime_sth->execute;
	};
	if($@ =~ /MySQL server has gone away/)
	{
		AppCore::DBI->clear_handle_cache;
		setup_modtime_sth();
		goto REPROCESS_MODTIME;
	}
	
	my $mod = $db_modtime_sth->fetchrow_hashref->{checksum};
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
	$dispatch->process($q);
}
