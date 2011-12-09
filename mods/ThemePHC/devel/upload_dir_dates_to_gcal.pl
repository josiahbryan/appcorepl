#!/usr/bin/perl
use strict;

use lib '/var/www/html/appcore/lib';

use AppCore::Web::Common;
use AppCore::Web::Module;
use ThemePHC::Directory;

my $demo_entry = q{
<entry xmlns='http://www.w3.org/2005/Atom'
    xmlns:gd='http://schemas.google.com/g/2005'>
  <category scheme='http://schemas.google.com/g/2005#kind'
    term='http://schemas.google.com/g/2005#event'></category>
  <title type='text'>Tuesday Tennis Lessons with Jane</title>
  <content type='text'>Meet on Tuesdays for a quick lesson.</content>
  <gd:transparency
    value='http://schemas.google.com/g/2005#event.opaque'>
  </gd:transparency>
  <gd:eventStatus
    value='http://schemas.google.com/g/2005#event.confirmed'>
  </gd:eventStatus>
  <gd:where valueString='Rolling Lawn Courts'></gd:where>
  <gd:recurrence>DTSTART;VALUE=DATE:20100505
DTEND;VALUE=DATE:20100506
RRULE:FREQ=WEEKLY;BYDAY=Tu;UNTIL=20100904
</gd:recurrence>
</entry>


};

# POST https://www.google.com/calendar/feeds/default/private/full

# POST /accounts/ClientLogin HTTP/1.0
# Content-type: application/x-www-form-urlencoded
# 
# accountType=HOSTED_OR_GOOGLE&Email=jondoe@gmail.com&Passwd=north23AZ&service=cl&
#    source=Gulp-CalGulp-1.05

# 
# HTTP/1.0 200 OK
# Server: GFE/1.3
# Content-Type: text/plain
# 
# SID=DQAAAGgA...7Zg8CTN
# LSID=DQAAAGsA...lk8BBbG
# Auth=DQAAAGgA...dk3fA5N
# 
#  ~~~~~~~~~
# 
# HTTP/1.0 403 Access Forbidden
# Server: GFE/1.3
# Content-Type: text/plain
# 
# Url=http://www.google.com/login/captcha
# Error=CaptchaRequired
# CaptchaToken=DQAAAGgA...dkI1LK9
# CaptchaUrl=Captcha?ctoken=HiteT4b0Bk5Xg18_AcVoP6-yFkHPibe7O9EqxeiI7lUSN



# Authorization: GoogleLogin auth=yourAuthValue


# 
# use LWP::UserAgent;
# my $ua = new LWP::UserAgent;
# 
# my $req = new HTTP::Request 'POST','https://www.google.com/accounts/ClientLogin';
# $req->content_type('application/x-www-form-urlencoded');
# 
# my %post = (
# 	accountType => 'HOSTED_OR_GOOGLE',
# 	Email => 'faith08@gmail.com',
# 	Passwd => 'lugubrious',
# 	service => 'cl',
# 	source => 'MyPleasantHillChurch.org-2.0'
# );
# #my @post_data = map { $_.'='.url_encode($post{$_}) } keys %post;
# my @post_data = map { $_.'='.$post{$_} } keys %post;
# my $post_str = join '&', @post_data;
# #die Dumper \@post_data, $post_str;
# $req->content($post_str);
# 
# my $res = $ua->request($req);
# print $res->as_string;

# Got this from the above block:


sub post_data
{
	my $url = shift;
	my $post = shift;
	use LWP::UserAgent;
	my $ua = new LWP::UserAgent;
	
	$url .= '?gsessionid=E4iDXWdy0Dh-iNP2NVuR-Q';
	
	my $req = new HTTP::Request 'POST',$url;
	my $authId = 'DQAAAJwAAABTWm7_cvRN8ZZ6BmBfRQyNs4c9Skd9aQLB-gkMSfBpZ80vVJTPVZb_ESGWmfXGU3zlCL8to7Qgn-bEI5shuFbw88qTCH5KGnORmsRp0xjN9JqSodEuSYfiKho6S4v68VtgVrxHlBsTOsT6Zp3H50NK1FpIJz2uJWfU5rCQaAbXt5jB7wI6A7vBvBWJV3CkC_eEHUUA87Ek2XbIC4fe0Ns8';
	
	$req->header('Authorization' => 'GoogleLogin auth='.$authId);
	

	my $post_str;
	if(!ref $post)
	{
		$req->content_type('application/atom+xml');
		$post_str = $post;
	}
	else
	{
		$req->content_type('application/x-www-form-urlencoded');
		my @post_data = map { $_.'='.url_encode($post->{$_}) } keys %$post;
		#my @post_data = map { $_.'='.$post{$_} } keys %$post;
		$post_str = join '&', @post_data;
		#die Dumper \@post_data, $post_str;
	}
	
	$req->content($post_str);
	
	my $res = $ua->request($req);
	my $res = $res->as_string;
	print STDERR "$res\n";
	return $res;
	
}



# <gd:where valueString='Rolling Lawn Courts'></gd:where>
# <content type='text'></content>
my $demo_entry = qq{
<entry xmlns='http://www.w3.org/2005/Atom'
    xmlns:gd='http://schemas.google.com/g/2005'>
  <category scheme='http://schemas.google.com/g/2005#kind'
    term='http://schemas.google.com/g/2005#event'></category>
  <title type='text'>Josiah Bryan's Birthday</title>
  <gd:transparency
    value='http://schemas.google.com/g/2005#event.opaque'>
  </gd:transparency>
  <gd:eventStatus
    value='http://schemas.google.com/g/2005#event.confirmed'>
  </gd:eventStatus>
  <gd:recurrence>DTSTART;VALUE=DATE:20111116
RRULE:FREQ=YEARLY
</gd:recurrence>
    <gd:reminder minutes='10080' method='email' />
    <gd:reminder minutes='5760' method='alert' />
</entry>


};

#post_data('https://www.google.com/calendar/feeds/default/private/full',$demo_entry);
#die "Test done";


#my $ts_file = '/tmp/phc-dir-ts.txt';
#my $current_ts = PHC::Directory->directory_timestamp();

my $directory_data = PHC::Directory->load_directory(0, 99999); # NOTE: Assuming a max of 10k families in this church! :-) JB 20110627
my @directory = @{$directory_data->{list}};

#y $tmpl = AppCore::Web::Common::load_template(${root}.'/mods/ThemePHC/tmpl/directory/sheet.tmpl');
my $cnt = 1;
my %mo2nbr = map { $_ => $cnt++ } qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
my %nbr2mo = map { $mo2nbr{$_} => $_ } keys %mo2nbr;

sub mo_to_nbr
{
	my $mo = shift;
	my $nbr = $mo2nbr{$mo} || die "Unknown month: '$mo'";
	return $nbr;
}

sub normalize_date 
{
	my $raw = shift;
	my $iso = shift;
	return undef if !$raw;
	#return 1 if !$raw;

=begin1

Apr 15
07/06/98
01/29/2004
1983-02-03
2-11-50
4-26
10-Jun
8/5

=cut
	#print $raw,"\n";
	my ($yr,$mo,$da);
	if($raw =~ /^([a-zA-Z]{3})\s(\d{1,2})$/)
	{
		# Match:
		# Apr 15
		$yr = undef;
		$mo = mo_to_nbr($1);
		$da = $2 + 0;
	}
	elsif($raw =~ /^(\d{1,2})[\/-](\d{1,2})[\/-](\d{2,4})$/)
	{
		# Match: 
		# 07/06/98
		# 01/29/2004
		# 2-11-50

		$yr = $3;
		$mo = $1;
		$da = $2;
	}
	elsif($raw =~ /^(\d{4})-(\d{1,2})-(\d{1,2})$/)
	{
		# Match:
		# 1983-02-03
		($yr,$mo,$da) = ($1,$2,$3);
	}
	elsif($raw =~/^(\d{1,2})[\/-](\d{1,2})$/)
	{
		# Match:
		# 4-26
		# 8/5
		$yr = undef;
		$mo = $1;
		$da = $2;
	}
	elsif($raw =~ /^(\d{1,2})-([a-zA-Z]{3})$/)
	{
		$yr = undef;
		$mo = mo_to_nbr($2);
		$da = $1;
	}
	else
	{
		$! = 'Unrecognized date: '.$raw;
		return undef;
	}

	#print $raw,"\n";
	if(!$yr)
	{
		return '2011'.rpad($mo).rpad($da) if $iso;
		return $nbr2mo{$mo+0}.' '.rpad($da);
	}
	elsif($iso)
	{
		$yr = $yr > 12 ? 1900+$yr : 2000 + $yr if $yr < 100;
		return $yr.rpad($mo).rpad($da);

	}
	else
	{
		$yr = $yr > 12 ? 1900+$yr : 2000 + $yr if $yr < 100;
		return rpad($mo).'/'.rpad($da).'/'.substr($yr,2,2);
	}

	return undef;
}

sub create_event 
{
	my $title = shift;
	my $date = shift;
	
	my $text = shift;
	
	$title = encode_entities($title);
	$text = encode_entities($text);
	
	return if !$date;

	my $norm_date = normalize_date($date,1);
	print STDERR "Unable to normalize '$date' for '$title': $!\n" if !$norm_date;
	
	print "$norm_date: $title\n";
	
	my $entry = qq{
<entry xmlns='http://www.w3.org/2005/Atom'
    xmlns:gd='http://schemas.google.com/g/2005'>
  <category scheme='http://schemas.google.com/g/2005#kind'
    term='http://schemas.google.com/g/2005#event'></category>
  <title type='text'>$title</title>
  <content type='text'>$text</content>
  <gd:transparency
    value='http://schemas.google.com/g/2005#event.opaque'>
  </gd:transparency>
  <gd:eventStatus
    value='http://schemas.google.com/g/2005#event.confirmed'>
  </gd:eventStatus>
  <gd:recurrence>DTSTART;VALUE=DATE:$norm_date
RRULE:FREQ=YEARLY
</gd:recurrence>
    <gd:reminder minutes='10080' method='email' />
    <gd:reminder minutes='5760' method='alert' />
</entry>
};
#die $entry;
	my $res = post_data('https://www.google.com/calendar/feeds/default/private/full',$entry);
	die $res if $res =~ /sessionid/;

}

my $root = AppCore::Config->get('WWW_DOC_ROOT').AppCore::Config->get('WWW_ROOT');
my $tmpl = AppCore::Web::Common::load_template(${root}.'/mods/ThemePHC/tmpl/directory/entry-text.tmpl');

my $found = 0;
foreach my $entry (@directory)
{
# 	if($entry->{last} eq 'Fisher')
# 	{
# 		$found = 1;
# 		next;
# 	}
# 	next if !$found;
	
	$tmpl->param($_ => $entry->{$_}) foreach keys %$entry;
	my $entry_text = $tmpl->output;
	#die $entry_text;
	
	# birthday, spouse_birthday, anniversary, and kids birthdays
	create_event($entry->{first}.' '.$entry->{last}.' Birthday', $entry->{birthday}, $entry_text);
	create_event($entry->{spouse}.' '.$entry->{last}.' Birthday', $entry->{spouse_birthday}, $entry_text) if $entry->{spouse};
	create_event($entry->{first}.' & '.$entry->{spouse}.' '.$entry->{last}.' Anniversary', $entry->{anniversary}, $entry_text) if $entry->{anniversary};
	my $kids = $entry->{kids};
	foreach my $kid (@$kids)
	{
		my $disp = $kid->{display};
		#$disp .= ' '.$entry->{last} if $disp !~ /\s/;
		create_event($disp.' Birthday (Child of '.$entry->{display}.')', $kid->{birthday}, $entry_text) if $kid->{display};
	}
}


