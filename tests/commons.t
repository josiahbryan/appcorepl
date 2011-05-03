#!/usr/bin/perl

use lib '../lib';
use lib 'lib';
use strict;

use Test::More;

# Load modules
{	
	undef $@;
	eval 'use AppCore::Common';
	is($@, '',
		'AppCore::Common load');
		
	undef $@;
	eval 'use AppCore::Web::Common';;
	is($@, '',
		'AppCore::Web::Common load');
}


# Test AppCore::Common
{
	my $got;
	my $pkg = 'AppCore::Common';
	
	# Dumper
	my $hash = { foo => 'framitz', bat => 'baz' };
	$got = Dumper($hash);
	like( $got, qr/framitz/, "$pkg/Dumper");
	
	# context
	$got = ref $pkg->context;
	is( $got, 'AppCore::RunContext', "$pkg/context");
	
	# pad
	$got = pad('x',8,' ');
	is( length($got), 8, "$pkg/pad - length");
	like( $got, qr/^x\s{7}$/, "$pkg/pad - regex");
	
	$got = pad('x1234',2,' ');
	is( length($got), 5, "$pkg/pad - length (smaller than arg)");
	
	$got = $pkg->pad('x',8,' ');
	like( $got, qr/^x\s{7}$/, "$pkg/pad - called as member");
	
	# rpad
	$got = rpad('10',4,'0');
	is( length($got), 4, "$pkg/rpad - length");
	like( $got, qr/^0{2}10$/, "$pkg/rpad - regex");
	
	$got = $pkg->rpad('10',4,'0');
	like( $got, qr/^0{2}10$/, "$pkg/rpad - called as member");
	
	
# 	min 
# 	max
# 	commify 
# 	
# 	called_from 
# 	print_stack_trace
# 		
# 	if_defined 
# 	is_print 
# 	inlist 
# 	in_acl_list
# 	peek
# 		
# 	send_email
# 	
# 	date_math 
# 	stamp 
# 	nice_date 
# 	date 
# 	dt_date
# 	simple_duration_to_hours
# 	to_delta_string
# 	delta_minutes
# 	seconds_since
# 	iso_date_to_seconds
# 	
 	#read_file 
 	my $tmp = "/tmp/file$$.dat";
 	my $test_str = "$$\n";
 	
 	open(FILE, ">$tmp") || die "Cannot test, cannt open $tmp for writing: $!";
 	print FILE $test_str;
 	close(FILE);
 	
 	$got = read_file($tmp);
 	is($got, $test_str, 
 		"$pkg/read_file");
 	
 	$got = $pkg->read_file($tmp);
 	is($got, $test_str, 
 		"$pkg/read_file - called as member");
 	
 	$test_str = "$0($$)\n";
 	undef $@;
 	eval { write_file($tmp, $test_str); };
 	is($@, '', 
 		"$pkg/write_file - no errors");
 	
 	$got = read_file($tmp);
 	is($got, $test_str, 
 		"$pkg/write_file - readback");
 	
 	unlink($tmp);
 	
 	#write_file
# 	
# 	parse_csv 
# 	
# 	taint_sql 
# 	taint_sys 
# 	taint_text 
# 	taint_number 
# 	taint
# 	
 	
 	#guess_title
#  	$name =~ s/([a-z])([A-Z])/$1 $2/g;
# 	$name =~ s/([a-z])_([a-z])/$1.' '.uc($2)/segi;
# 	$name =~ s/^([a-z])/uc($1)/seg;
# 	$name =~ s/\/([a-z])/'\/'.uc($1)/seg;
# 	$name =~ s/\s([a-z])/' '.uc($1)/seg;
# 	$name =~ s/\s(of|the|and|a)\s/' '.lc($1).' '/segi;
# 	$name .= '?' if $name =~ /^is/i;
# 	$name =~ s/id$//gi;
# 	my $chr = '#';
# 	$name =~ s/num$/$chr/gi; 
# 	$name =~ s/datetime$/Date\/Time/gi;
# 	$name =~ s/\best\b/Est./gi;
	is(guess_title("fooBar"),"Foo Bar", "$pkg/guess_title - camel case, spacing, first letter");
	is(guess_title("foo_bar"),"Foo Bar", "$pkg/guess_title - underscore");
	is(guess_title("foo of bar"),"Foo of Bar", "$pkg/guess_title - of lc");
	is(guess_title("fooTheBar"),"Foo the Bar", "$pkg/guess_title - the lc");
	is(guess_title("foo_and_bar"),"Foo and Bar", "$pkg/guess_title - and lc");
	is(guess_title("foo_aBar"),"Foo a Bar", "$pkg/guess_title - a lc");
	is(guess_title("is_flag"),"Is Flag?", "$pkg/guess_title - is > ?");
	is(guess_title("flag_id"),"Flag ", "$pkg/guess_title - 'id' removal");
	is(guess_title("flag_num"),"Flag #", "$pkg/guess_title - num > #");
	is(guess_title("datetime"),"Date/Time", "$pkg/guess_title - datetime");
	is(guess_title("flag_est"),"Flag Est.", "$pkg/guess_title - est");
	is(guess_title("flag/test"),"Flag/Test", "$pkg/guess_title - slash");
 	
 	
# 	
# 	MY_LINE
# 	SYS_PATH_BASE 
# 	SYS_PATH_MODULES
# 	SYS_PACKAGE_BASE

}

# Test AppCore::Web::Common
{
	my $got;
	my $pkg = 'AppCore::Web::Common';
	
# get_full_url 
	$ENV{SCRIPT_NAME} = 'foo';	
	$ENV{PATH_INFO} = 'bar';
	$ENV{QUERY_STRING} = '';
	is(get_full_url(), 'foobar', "$pkg/get_full_url - no query");
	
	$ENV{QUERY_STRING} = 'baz';
	is(get_full_url(), 'foobar?baz', "$pkg/get_full_url - query");
	
# url_encode 
	my $test = 'foobar?baz+foo';
	my $expect = 'foobar%3Fbaz%2Bfoo';
	$got = url_encode($test);
	is($got, $expect, "$pkg/url_encode");
	
# url_decode 
	$got = url_decode($got);
	is($got, $test, "$pkg/url_decode");


# escape 
# unescape
# param 
# Vars
# redirect 
# getcookie 
# setcookie 
# load_template 
# error
# remove_stopwords
# html2text
# clean_html	

}

done_testing();

