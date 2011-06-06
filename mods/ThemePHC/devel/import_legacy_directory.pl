#!/usr/bin/perl

use lib '/var/www/html/appcore/lib';
use AppCore::DBI;
use AppCore::User;
use AppCore::Web::Module;
use AppCore::Web::Common;
use ThemePHC::Directory;

my $data = PHC::Directory->read_legacy_xls('mods/ThemePHC/devel/Data.xls');

my @string_cols = qw/
	first
	last 
	photo_num
	birthday
	cell
	email
	home
	address
	spouse
	spouse_birthday
	spouse_cell
	spouse_email
	anniversary
	comments
	display
/;

my @bool_cols = qw/
	incomplete_flag
	p_cell_dir
	p_cell_onecall
	p_email_dir
	p_spouse_cell_dir
	p_spouse_cell_onecall
	p_spouse_email_dir
/;

use Data::Dumper;

foreach my $entry (@$data)
{
	my $fam = PHC::Directory::Family->find_or_create( first => $entry->{first}, last => $entry->{last} );
	
	foreach my $col (@string_cols)
	{
		next if !$col;
		my $val = $entry->{$col};
		$val =~ s/(^\s+|\s+$)//g;
		if($fam->get($col) ne $val)
		{
			#print STDERR "Setting $entry->{display}/$col to '$val'\n";
			$fam->set($col, $val);
		}
	}
	
	foreach my $col (@bool_cols)
	{
		next if !$col;
		my $val = $entry->{$col};
		$val =~ s/(^\s+|\s+$)//g;
		my $bool = $val ? 1:0;
		#print STDERR "Col: $col\n";
		if($fam->get($col) != $bool)
		{
			#print STDERR "Setting $entry->{display}/$col to '$bool'\n";
			$fam->set($col, $bool); 
		}
	}
	
	if($fam->is_changed)
	{
		print STDERR "Updated ".$fam->display."\n";
		$fam->update; 
	}
	
	foreach my $kid_entry (@{$entry->{kids} || []})
	{
		my $kid = PHC::Directory::Child->find_or_create( familyid => $fam, display => $kid_entry->{name} );
		
		my ($first, $last) = split /\s/, $kid_entry->{name};
		$kid->first($first) if $kid->first ne $first;
		$kid->last($last) if $kid->last ne $last;
		$kid->birthday($kid_entry->{bday}) if $kid->birthday ne $kid_entry->{bday};
		 
		$kid->update if $kid->is_changed;
		#print STDERR "$entry->{display}: Kid '$first|$last', (bday '$kid_entry->{bday}') id $kid\n";
	}
	
}