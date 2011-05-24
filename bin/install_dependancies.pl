#!/usr/bin/perl
use strict;
use CPAN;
# Also follow http://www.cyberciti.biz/tips/rhel-centos-fedora-apache2-fastcgi-php-configuration.html to setup FastCGI (not the PHP part tho)
system("yum install -y mysql mysql-devel mysql-client mysql-server");
my @deps = qw/
	HTML::Template
	ExtUtils::MakeMaker
	Params::Validate
	DateTime::Locale
	DateTime::TimeZone
	DateTime
	Class::DBI
	LWP::Simple
	FCGI
	JSON::XS
	MIME::Lite
	Clone::Fast
/;

foreach my $dep (@deps)
{
	CPAN::install($dep);
}
