#!/usr/bin/perl
use strict;
use lib '../lib';
use lib 'lib';
use AppCore::DBI;
use AppCore::Web::Module;

use Content::Page;

my $home_type = Content::Page::Type->find_or_create({
	name		=> 'Home Page',
	controller	=> 'Content::Page::Controller',
	view_code	=> 'home',
});

Content::Page->find_or_create({
	typeid	=> $home_type,
	url	=> '/', # root
	title	=> 'Hello, World!',
	content => 'What wonderful things God hath wroght!'
});
	
my $sub_type = Content::Page::Type->find_or_create({
	name		=> 'Static Sub-Page',
	controller	=> 'Content::Page::Controller',
	view_code	=> 'sub',
});

Content::Page->find_or_create({
	typeid	=> $sub_type,
	url	=> '/welcome', # root
	title	=> 'Welcome %%use_first%%',
	content => '<h1>Hello, %%use_first%%!</h1>'
});
	
