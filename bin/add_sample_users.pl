#!/usr/bin/perl
use strict;
use lib '../lib';
use lib 'lib';
use AppCore::DBI;
use AppCore::User;

my $admin_group = AppCore::User::Group->find_or_create({ name => 'ADMIN' });

my $admin_user  = AppCore::User->find_or_create({
	user	=> 'admin',
	pass	=> 'admin',
	first	=> 'Admin',
	email	=> 'admin@example.com',
	photo	=> '/mods/User/user_photos/generic_photo.jpg',
});
	
AppCore::User::GroupList->find_or_create({
	userid	=> $admin_user,
	groupid	=> $admin_group,
});