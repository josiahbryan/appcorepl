#!/usr/bin/perl
use strict;
use lib '/var/www/html/appcore/lib';
use AppCore::DBI;
use AppCore::Web::Module;
use ThemePHC::Directory;


my $ts_file = '/tmp/phc-dir-ts.txt';
my $current_ts = PHC::Directory->directory_timestamp();
	
my $changed = 0;
if($ARGV[0])
{
	$changed = 1;
}
else
{
	my $last_gen_ts;
	open(TS,"<$ts_file");
	$last_gen_ts = <TS>;
	close(TS);
	
	$changed = 1 if $last_gen_ts ne $current_ts;
}

if($changed)
{
	PHC::Directory->generate_pdf;
	
	open(TS,">$ts_file");
	print TS $current_ts;
	close(TS);
}
else
{
	#print "Not making new PDF, nothing changed!\n";
}