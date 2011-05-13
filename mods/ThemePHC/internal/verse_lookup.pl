#!/usr/bin/perl

use strict;

# Adjust if appcore located in a different location...
use lib '/var/www/html/appcore/lib';
use AppCore::Common;
use ThemePHC::VerseLookup;

my $file = $ARGV[0] || die "No ref filename given";

if($file eq '-fix')
{
	my @nulls = ThemePHC::VerseLookup->retrieve_from_sql('title is null');
	foreach my $cache (@nulls)
	{
		my $ref = $cache->verse_ref;
		print STDERR "Fixing '$ref'\n";
		ThemePHC::VerseLookup->get_verse($ref);
		$cache->delete if $cache->title;
	}
}
else
{
	my $ref = `cat $file`;
	$ref =~ s/[\r\n]//g;
	
	ThemePHC::VerseLookup->get_verse($ref);
	
	unlink($file);
}
