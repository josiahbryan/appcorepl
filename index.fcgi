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

my $req_counter  = 0;
my $MAX_REQUESTS = 500;
my $MEM_LIMIT    = 500;

while(my $q = CGI::Fast->new)
{
	$ENV{HTTP_HOST}   = $ENV{HTTP_X_FORWARDED_HOST} if $ENV{HTTP_X_FORWARDED_HOST};
	$ENV{REMOTE_ADDR} = $ENV{HTTP_X_FORWARDED_FOR}  if $ENV{HTTP_X_FORWARDED_FOR};
	if($ENV{REMOTE_ADDR} =~ /^180\.76\./) # too much traffic from china
	{
		print "Content-Type: text/plain\n\nToo much traffic from your subnet, please contact josiahbryan\@gmail.com to remove the block.\n\n";
		next;
	}
	if($ENV{REMOTE_ADDR} =~ /^188\.143./)
	{
		print "Content-Type: text/plain\n\nToo many hacking attempts from your subnet, please contact josiahbryan\@gmail.com to remove the block.\n\n";
		next;
	}
	#print STDERR "Passing '$ENV{REMOTE_ADDR}'\n";
	
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
		AppCore::DBI->clear_cached_dbobjects;
		goto REPROCESS_MODTIME;
	}
	
	if($last_mod && ($mod > $last_mod || time - $last_mod > 60 * 5))
	{
		#print STDERR "Database updated, clearing cached object index... ($mod > $last_mod)\n";
		print STDERR "$0: Clearing object index...\n";
		AppCore::DBI->clear_cached_dbobjects;
	}
	else
	{
		#print STDERR "No DB Change ($mod < $last_mod)\n";
	}
	$last_mod = $mod;
	
	#print STDERR "index.fcgi: modtime: $last_mod\n";
	
	$dispatch->process($q);

	my $cur_mem = int(int(`/bin/ps -o vsz= $$`) / 1024);
	
	if($cur_mem > $MEM_LIMIT)
	{
		print STDERR "Exiting, memory usage is $cur_mem MB, limit is $MEM_LIMIT MB\n";
		exit;
	}
	else
	{
		#print STDERR "[Debug] memory audit: $cur_mem MB, limit $MEM_LIMIT MB, safe so far\n";
	}
	
	if($req_counter ++ > $MAX_REQUESTS)
	{
		print STDERR "$0 exiting, served $req_counter requests\n";
		exit;
	}
}
