#!/usr/bin/perl

use lib '../lib';
use lib 'lib';
use strict;

use Test::More;

# Load modules
{	
	undef $@;
	eval 'use AppCore::Config';
	is($@, '',
		'AppCore::Config load');
		
	undef $@;
	eval 'use AppCore::Common';
	is($@, '',
		'AppCore::Common load');
		
	undef $@;
	eval 'use AppCore::Web::Common';;
	is($@, '',
		'AppCore::Web::Common load');
}

# Content 'mod' is required
{
	undef $@;
	eval 'use Content';
	is($@, '',
		'Content mod found');
};


done_testing();