#!/usr/bin/perl
use strict;
use lib '../lib';
use lib 'lib';
use AppCore::DBI;
use AppCore::Web::Module;

use Content::Page;

my $type = Content::Page::Type->find_or_create({
	description	=> 'Static Page',
	controller	=> 'Content::Page::Controller',
});

Content::Page->find_or_create({
	typeid	=> $type,
	url	=> '/', # root
	title	=> 'Hello, World!',
	content => 'What wonderful things God hath wroght!'
});
	
