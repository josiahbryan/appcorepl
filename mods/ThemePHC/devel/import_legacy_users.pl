#!/usr/bin/perl

use strict;

use lib '../../../lib';
use AppCore::Common;
use AppCore::User;

package PHC::DbSetup;
{
	our $DbPassword = AppCore::Common->read_file('../pci_db_password.txt');
	{
		$DbPassword =~ s/[\r\n]//g;
	}
	
	our @DbConfig = (
	
		'phc',		# Database ('schema')
		'database',	# Host
		'root', 	# User
		$PHC::DbSetup::DbPassword,
	);
	
	# Reference in class meta as:
	# @PHC::DbSetup::DbConfig
}

package PHC::LegacyUser;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->setup_default_dbparams(@PHC::DbSetup::DbConfig);
	
	__PACKAGE__->meta({
		
		table		=> 'users',
		
		schema	=> 
		[
			{ field => 'userid',		type => 'int', auto => 1},
			{ field	=> 'user',		type => 'varchar(255)' },
			{ field	=> 'pass',		type => 'varchar(255)' },
			{ field	=> 'display',		type => 'varchar(255)' },
			{ field	=> 'email',		type => 'varchar(255)' },
			{ field	=> 'bio',		type => 'text' },
			{ field	=> 'picture_file',	type => 'varchar(255)' },	
			{ field	=> 'login_count',	type => 'int' },
			{ field	=> 'last_seen',		type => 'datetime' },
			{ field	=> 'pagehit_count',	type => 'int' },
			{ field	=> 'comment_count',	type => 'int' },
			{ field	=> 'is_temp',		type => 'int(1)' },
			{ field	=> 'temp_uuid',		type => 'varchar(255)' },
			{ field => 'allow_dir',		type => 'int(1)' },
			
		],
	
	});
};

package main;
{
	use Data::Dumper;
	
	my $MODE = 'allow_dir';
	
	my $AppCoreSchema = 
	[
		{
			'field'	=> 'userid',
			'extra'	=> 'auto_increment',
			'type'	=> 'int(11)',
			'key'	=> 'PRI',
			readonly=> 1,
			auto	=> 1,
			map_from => 'userid'
		},
		{	field	=> 'user',		type	=> 'varchar(255)',	map_from => 'user' },
		{	field	=> 'pass',		type	=> 'varchar(255)',	map_from => 'pass' },
		{	field	=> 'email',		type	=> 'varchar(255)',	map_from => 'email' },
		{	field	=> 'first',		type	=> 'varchar(255)' },
		{	field	=> 'last',		type	=> 'varchar(255)' },
		{	field	=> 'display',		type	=> 'varchar(255)',	map_from => 'display' },
		{	field	=> 'photo',		type	=> 'varchar(255)',	map_from => 'picture_file' },
		{	field	=> 'location',		type	=> 'varchar(255)' },
		{	field	=> 'tz_off',		type	=> 'float',	  default => -4 },
		{	field	=> 'notes',		type	=> 'text',		map_from => 'bio'	  },
		{	field	=> 'is_fbuser',		type	=> 'int(1)',	  default =>  0 },
		{	field	=> 'fb_user',		type	=> 'varchar(255)' },
		{	field	=> 'fb_token',		type	=> 'varchar(255)' },
		{	field	=> 'fb_token_expires',	type	=> 'datetime'     },
		{	field	=> 'extra_data',	type	=> 'text'	  },
		{ 	field	=> 'last_seen',		type	=> 'datetime',		map_from => 'last_seen' },
		{	field	=> 'hitcount',		type	=> 'int(11)',	  null => 0, default => 0, 		map_from => 'pagehit_count'  },
	];
	
	our %fieldmap = map { $_->{map_from} => $_->{field} } @$AppCoreSchema;
	
	my @all_users = PHC::LegacyUser->retrieve_from_sql('1 order by userid');
	my $max_id = @all_users ? $all_users[$#all_users]->id : -1;
	foreach my $user (@all_users)
	{
		next if $user->id == 1;
		
		my $acu = AppCore::User->retrieve($user->id);
		if($acu && $acu->id != 1)
		{
			$max_id ++;
			#print STDERR "Conflict at id $user: legacy: ".$user->display.", acu: ".$acu->display." (max id: $max_id)\n";
		}
		
		if($MODE eq 'allow_dir')
		{
			if(!$acu)
			{
				print STDERR "Huh...didnt find ACU for ".$user->display."\n";
			}
			elsif($user->allow_dir)
			{
				my $refid = AppCore::User::GroupList->find_or_create(userid => $acu, groupid => 3);
				print STDERR "Updated groups, added user $acu, '".$acu->display."', to directory group\n";
			}
		}
		else
		{
			if(!$acu)
			{
				my ($first,$last) = split /\s/, $user->display;
				my $new_user = {
					first => $first,
					last  => $last,
				};
				
				foreach my $old_field (keys %fieldmap)
				{
					next if !$old_field;
					$new_user->{$fieldmap{$old_field}} = $user->get($old_field) || '';
				}
				
				#die Dumper $new_user;
				my $new_ref = AppCore::User->create($new_user);
				if($new_ref->id != $user->id)
				{
					die "Ooops...ID's didn't copy for userid $user (newid $new_ref)";
				}
				else
				{
					print "Imported $new_ref - ".$new_ref->display."\n";
				}
			}
		}
	}
	
};

1;

