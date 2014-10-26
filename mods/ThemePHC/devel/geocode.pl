#!/usr/bin/perl
use strict;

use LWP::Simple qw/get/;

use lib '/var/www/html/appcore/lib';
use AppCore::DBI;
use AppCore::User;
use AppCore::Web::Module;
use AppCore::Web::Common;
use ThemePHC::Directory;

my $directory_data = PHC::Directory->load_directory(0, 99999); # NOTE: Assuming a max of 10k families in this church! :-) JB 20110627
my @directory = @{$directory_data->{list}};

sub geocode_entry
{
	my $fam = shift;
	my $entry = PHC::Directory::Family->retrieve($fam->{familyid});
	my $dont_update = shift || 0;
	my $url = "http://maps.google.com/maps?q=".$entry->address;
	my $content = LWP::Simple::get($url);
	#die "Couldn't get it!" unless defined $content;
	print STDERR "Error geocoding entry $entry, address:".$entry->address.": No content returned from $url\n" if !$content;
	#my $content = "viewport:{center:{lat:40.199858,lng:-84.809039},span:{lat:0.006295,lng:0.006295},zoom:16";
	my ($lat,$lng) = ($content=~/center:\s*{lat:\s*(.*?),\s*lng:\s*(.*?)}/);
	$entry->lat($lat);
	$entry->lng($lng);
	$entry->update unless $dont_update;
	$fam->{lat} = $lat;
	$fam->{lng} = $lng;
	return $entry;
}

# 
# my $addr = shift || "313 1/2 W Oak St, Union City, IN";
# my $content = get("http://maps.google.com/maps?q=$addr");
# die "Couldn't get it!" unless defined $content;
# #my $content = "viewport:{center:{lat:40.199858,lng:-84.809039},span:{lat:0.006295,lng:0.006295},zoom:16";
# my ($lat,$lng) = ($content=~/center:\s*{lat:\s*(.*?),\s*lng:\s*(.*?)}/);
# 
# print "Lat/Lng: $lat, $lng\n";
# 
# if(!$lat || !$lng)
# {
# 	print $content;
# }

use GIS::Distance;
my $gis = GIS::Distance->new();

my $lat_convx = 69;
my $lng_convy = 49;

sub _distance 
{
	my ($x1,$y1,$x2,$y2) = @_;
	my $dx = ($x1*$lat_convx) - ($x2*$lat_convx);
	my $dy = ($y1*$lng_convy) - ($y2*$lng_convy);
	return sqrt($dx*$dx+$dy*$dy);
	

}

my $MilesDiff = 2.75;

my %opts = 
(
	circle => 1,
	line   => 1,
	text   => 1,
	log    => 1,
	scale  => 10,
	circle_max => 60,
	circle_min => 5,
);

my $grid = {};
my $count = 0;
foreach my $fam (@directory)
{
	next if !$fam->{address};
	#next if !($fam->{address} =~ /(Dayton|Parker)/) || $fam->{address} =~ /Spook/;; 
	if(!$fam->{lat} || !$fam->{lng})
	{
		geocode_entry($fam);
		print STDERR "Geocode $fam->{display}: $fam->{lat}, $fam->{lng}\n";
	}
	
	my $lat = $fam->{lat};
	my $lng = $fam->{lng};
	
	#my $mx = $lat * 69.1,  $my = $lng * 1.3043478;
	
	my $key = $lat.$lng;
	if(!$count)
	{
		$grid->{$key} = {
			lat => $lat,
			lng => $lng,
			list => [$fam]
		};
	}
	else
	{
		my $found = 0;
		foreach my $bucket (values %$grid)
		{
			#my $distance = $gis->distance( $lat,$lng, $bucket->{lat}, $bucket->{lng} );
			#my $dist = $distance->miles();
			my $dist = _distance( $lat,$lng, $bucket->{lat}, $bucket->{lng} );
			if($dist < $MilesDiff)
			{
				push @{$bucket->{list}}, $fam;
				$found = 1;
				last;
			}
		}
		
		if(!$found)
		{
			$grid->{$key} = {
				lat => $lat,
				lng => $lng,
				list => [$fam]
			};
		}
	}
	
	$count ++;
}

my $phc_lat = 40.30966;
my $phc_lng = -84.82437;

foreach my $bucket (values %$grid)
{
	#my $distance = $gis->distance( $phc_lat, $phc_lng, $bucket->{lat}, $bucket->{lng} );
	#my $dist = $distance->miles();
	my $dist = _distance( $phc_lat, $phc_lng, $bucket->{lat}, $bucket->{lng} );
	
# 	print "\t--------------------------\n";
# 	print "\t$dist miles from PHC\n";
# 	print "\t--------------------------\n";
	#die "bad dist $dist" if $dist > 100.;
	
	$bucket->{dist} = $dist;
}

my $count_total = 0;
my @list = sort {$a->{dist} <=> $b->{dist}} values %$grid;
foreach my $bucket (@list)
{
	print "$bucket->{dist} miles ($bucket->{lat}, $bucket->{lng}):\n";
	
	my @simple;
	foreach my $fam (@{$bucket->{list}})
	{
		print "\t ".$fam->{display}." \t ".$fam->{address}."\n";
		
		my $cnt = 0;
		$cnt++;
		$cnt++ if $fam->{spouse};
		my @kids = @{$fam->{kids}||[]};
		$cnt += scalar(@kids);
		
		$fam->{cnt} = $cnt;
		
		push @simple, {
			display => $fam->{display},
			address => $fam->{address},
			cnt => $cnt,
		};
		$count_total += $cnt;
	}
	
	$bucket->{simple} =
	{
		list => \@simple,
		dist => $bucket->{dist},	
	};
}
	
print STDERR "Processed $count, total people: $count_total\n";


use GD;
GD::Image->trueColor(1);	#improves quality

my $img = new GD::Image(768,768);
my ($width,$height) = $img->getBounds();
$img->filledRectangle(0,0,$width,$height,_color($img,'255,255,255'));#_color($img,'220,220,220'));
#$img->filledRectangle(0,0,$width,$height,_color($img,'220,220,220'));

# Max x/y in miles
my $max_radius = 65;
my $max_x = $max_radius * 2;
my $max_y = $max_radius * 2;

# 69 = lat to miles, 59 = lng to miles (all APPROX!)
my $scalex = $width  / $max_x;
my $scaley = $height / $max_y;

my $xconv = $lat_convx * $scalex;
my $yconv = $lng_convy * $scaley;

print STDERR "wh:      $width, $height\n";
print STDERR "maxxy:   $max_x, $max_y\n";
print STDERR "scalexy: $scalex, $scaley\n";
print STDERR "xyconv:  $xconv, $yconv\n";

# Top-left corner of the image in lat/lng
my $min_lat = $phc_lat - ($max_radius/$lat_convx);
my $min_lng = $phc_lng - ($max_radius/$lng_convy);

print STDERR "min lat,lng: $min_lat, $min_lng\n";
print STDERR "phc lat,lng: $phc_lat, $phc_lng\n";

my $center_x = ($phc_lat - $min_lat) * $xconv;
my $center_y = ($phc_lng - $min_lng) * $yconv; 

# draw a circle centered at center
#my $blue = _color($img,0,0,255);
#my $red  = _color($img,255,0,0);
my $green = _color($img,0,255,0);

#my $red  = _color($img,193,73,52);
my $red  = _color($img,193,59,36);
my $blue = _color($img,52,80,193);

# red 193,73,52
# blue 52,80,193

print STDERR "center_x: $center_x, center_y: $center_y\n";
#$img->filledArc($center_x, $center_y, 5,5, 0,359, $red);

use Math::Trig;

my $PI = 3.1415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170679821480865132823066470938446095505822317253594081284811174502841027019385211055596446229489549303819644288109756659334461;


sub scale_rate
{
	my $dist = shift;
	my $max = $max_radius;
	my $unit = $dist/$max;
	my $log = log($unit);
	my $log1 = 1-$log;
	#print "scale_rate: $dist, $log\n";
	return $opts{log} ? $dist*$log1 : $dist;
}

my @dots;
foreach my $bucket (@list)
{
	#my $phc_dx = $bucket->{lat} - $phc_lat;
	#my $phc_dy = $bucket->{lng} - $phc_lng;
		
	#$bucket->{lat} -= $phc_dx;
	#$bucket->{lng} -= $phc_dy;

	my $distance = $gis->distance( $phc_lat, $phc_lng, $bucket->{lat}, $bucket->{lng} );
	my $dist_miles = $distance->miles();
	$bucket->{dist_miles} = $dist_miles;
	
	$img->setAntiAliased($blue);
	
	#my $rads = atan(($bucket->{lat} - $phc_lat) / ($bucket->{lng} - $phc_lng));
	#my $degs = $rads * 180/$PI;
	
	my $a_dx = $bucket->{lng} - $phc_lng;
	my $a_dy = $bucket->{lat} - $phc_lat;
	
	my $theta = atan2(-$a_dy, $a_dx) * 360.0 / ($PI*2);
	
	my $theta_normalized = $theta < 0 ? $theta + 360 : $theta;

	if( abs(360 - $theta_normalized) < 0.001)
	{
		$theta_normalized = 0;
	}
	my $degs = $theta_normalized;
	my $rads = $degs * 0.0174532925;
	
	my $one_rad = 2 * $PI;
	my $qtr_rad = $one_rad / 4;
	
	#$rads += $qtr_rad*2;
	#$degs += 360/2; 
	
	#$degs += 360 if $degs < 0;
	
	my $dist = $bucket->{dist};
	$dist = scale_rate($dist);
	
	my $dot_x = ($dist * $scalex) * cos($rads) + $center_x;
	my $dot_y = ($dist * $scaley) * sin($rads) + $center_y;
	
	my $size_x = abs($dot_x - $center_x);
	my $size_y = abs($dot_y - $center_y);
	
	
	my @list = @{$bucket->{list}||[]};
	my @splits = split /\s*,\s*/, $list[0]->{address};
	my @last = @splits[-2, 2];
	#die Dumper \@last;
	my $city = shift @last;
	my $state = shift @last;
	$state =~ s/\s\d+$//g;
	
	
	print STDERR "\t $city: ($bucket->{lng}, $bucket->{lat}), $dist: angle: $degs, dot ($dot_x, $dot_y), size ($size_x, $size_y)\n";
	
	my ($lastx,$lasty);
	#my $rad =0 ;
	#for($rad=0; $rad < 2*$PI; $rad += (2*$PI)/1000.)
	for my $angle (0..360)
	{
		my $rads = $angle * 0.0174532925;
		my $dot_x = ($dist * $scalex) * cos($rads) + $center_x;
		my $dot_y = ($dist * $scaley) * sin($rads) + $center_y;
		if($lastx && $lasty)
		{
			#$img->filledArc($dot_x,$dot_y, 2,2, 0,359, $blue);
			_line($img,$lastx,$lasty,$dot_x,$dot_y, $blue, 1) if $opts{circle};
		}
		
		$lastx = $dot_x;
		$lasty = $dot_y;
	}
	
	
	
	my $cnt = 0;
	foreach my $entry (@list)
	{
		$cnt++;
		$cnt++ if $entry->{spouse};
		my @kids = @{$entry->{kids}||[]};
		$cnt += scalar(@kids);
	}
	$bucket->{people_cnt} = $cnt;
# 	
 	# Calc an approx size for the dot based on the number of people in the bucket (every 10 people gets 3 pixels larger in size)
 	my @list = @{$bucket->{list}||[]};
 	my $rel_size = $cnt / 10. * ($opts{scale}||20.);
 	$rel_size = $opts{circle_max} if $rel_size > $opts{circle_max};
 	$rel_size = $opts{circle_min} if $rel_size < $opts{circle_min};
 	
 	push @dots, [$dot_x,$dot_y,$rel_size,$bucket];
 	$bucket->{simple}->{dot_x} = $dot_x;
 	$bucket->{simple}->{dot_y} = $dot_y;
 	$bucket->{simple}->{dot_size} = $rel_size;
	
	# Draw a line connecting the center to the dot
	_line($img, $center_x, $center_y, $dot_x, $dot_y, $blue) if $opts{line};
}

#$img->filledArc($center_x, $center_y, 15,15, 0,359, $green);
#my $icon_file = '/opt/httpd-2.2.17/htdocs/appcore/mods/ThemePHC/images/phclogo-whitesq-50.jpg';
#my $icon_file = '/opt/httpd-2.2.17/htdocs/appcore/mods/ThemePHC/images/logo-white-textunder-250px.png';
my $icon_file = '/opt/appcore/mods/ThemePHC/images/logo-black-square.png';
my $icon = GD::Image->new($icon_file);
my @l_bounds = $icon->getBounds();
$img->copy($icon, $center_x - $l_bounds[0]/2 + 4,$center_y-$l_bounds[1]/2,0,0,$l_bounds[0],$l_bounds[1]);
#my $outw = $l_bounds[0]/4;
#my $outh = $l_bounds[1]/4;
#$img->copyResized($icon, $center_x - $outw/2 + ($outw * 10/250),$center_y-$outh/2,0,0,$outw,$outh,$l_bounds[0],$l_bounds[1]);

use Data::Dumper;
foreach my $dot_info (@dots)
{
	my @dot = @$dot_info;
	$img->setAntiAliased($red);
	$img->filledArc($dot[0],$dot[1],$dot[2],$dot[2], 0,359, gdAntiAliased);
}

my @bucket_simple;

foreach my $dot_info (@dots)
{
	my @dot = @$dot_info;

	my $bucket = $dot[3];
	my @list = @{$bucket->{list}||[]};
	my @splits = split /\s*,\s*/, $list[0]->{address};
	my @last = @splits[-2, 2];
	#die Dumper \@last;
	my $city = shift @last;
	my $state = shift @last;
	$state =~ s/\s\d+$//g;
	
# 	my $x = $hash{x};
# 	my $y = $hash{y};
# 	my $apt = $hash{pt} || $hash{apt} || $hash{size};
# 	my $c = $hash{c} || $hash{color};
# 	my $right_flag = $hash{right_flag};
# 	my $x_center = $hash{x_center};
# 	my $angle = $hash{angle};
# 	my $just_bounds = $hash{just_bounds};
# 	my $str = $hash{str};
	
	my $cnt = $bucket->{people_cnt};
	
	my $suffix = $cnt == 1 ? "person" : "people";
	my $miles = int($bucket->{dist_miles});
	my $str = $city . " ($cnt $suffix, $miles m)";
	
	$bucket->{simple}->{city} = $city;
	$bucket->{simple}->{dot_text} = $str;
	push @bucket_simple, $bucket->{simple};
	
	next if !$opts{text};
	
	my $offx = 4;
	my $offy = -4;
	for my $x (-1..1)
	{
		for my $y (-1..1)
		{
			_string($img,
			
				x => $dot[0]+$x+$offx,
				y => $dot[1]+$y+$offy,
				pt => 8,
				c => _color($img, 0,0,0),
				str => $str,
			);
		}
	}
	
	_string($img,
	
		x => $dot[0]+$offx,
		y => $dot[1]+$offy,
		pt => 8,
		c => _color($img, 255,255,255),
		str => $str,
	);
	
	#print STDERR "City: $city\n";
}


use JSON qw/encode_json/;
open(FILE,">circles.js");
print FILE "circle_data=".encode_json(\@bucket_simple);
close(FILE);

open(FILE,">circles.png");
print FILE $img->png;
close(FILE);
		

sub _line
{
	my $img = shift;
	my $x1 = shift;
	my $y1 = shift;
	my $x2 = shift;
	my $y2 = shift;
	my $color = shift;
	my $thick = shift || 1;
	
	$img->setAntiAliased($color);
	
	my $half = $thick/2;
	for(my $i=-1*$half;$i<$half;$i+=1) #0.15)
	{
		$img->line($x1-$i,$y1-$i,$x2-$i,$y2-$i,gdAntiAliased);
	}
	
	
	
}

my %colors;
sub _color($$)
{
	my $img = shift;
	my @a;
	my $s;
	if(@_ == 3 || @_ == 4)
	{
		@a = @_;
		$s = join ',', @a;
	}
	else
	{
		$s = shift;
		@a = split/,/, $s;
	}
	
	push @a,0 if @a == 3;
	#print STDERR "got color: $s, join:".join('|',@a)."\n";
		
	$colors{$s} = $img->colorAllocateAlpha(@a) if !defined $colors{$s};
	return $colors{$s};
}

sub _string
{
	#my ($img,$x,$y,$apt,$str,$c,$right_flag,$angle,$just_bounds) = @_;
	my $img = shift;
	my %hash = @_;
	my $x = $hash{x};
	my $y = $hash{y};
	my $apt = $hash{pt} || $hash{apt} || $hash{size};
	my $c = $hash{c} || $hash{color};
	my $right_flag = $hash{right_flag};
	my $x_center = $hash{x_center};
	my $angle = $hash{angle};
	my $just_bounds = $hash{just_bounds};
	my $str = $hash{str};
	#print STDERR "x=$x, y=$y, apt=$apt, str=\"$str\",c=\"$c\",right_flag=$right_flag,angle=$angle,just_bounds=$just_bounds\n";
	#my @pairs;
	#push @pairs,"x=".int($x/$g_width*100)."%","y=".int($y/$g_height*100)."%","apt=".int($apt/$g_width*100)."%","str=$str","c=$c","right_flag=$right_flag","angle=$angle";
	#s/\"/\\"/g foreach @pairs;
	#print '"'.join('","',@pairs).'"'."\n";

	my $ttf = '/usr/share/fonts/bitstream-vera/Vera.ttf';
	$right_flag = 1 if !$right_flag;
	
	my ($width,$height) = $img->getBounds();
	
	$angle = 0 if !$angle;
	$angle = 0.0174532925 * $angle; # convert to radian per google calculator
	
	#@bounds[0,1]  Lower left corner (x,y)
	#@bounds[2,3]  Lower right corner (x,y)
	#@bounds[4,5]  Upper right corner (x,y)
	#@bounds[6,7]  Upper left corner (x,y)
	
	#fgcolor    Color index to draw the string in
	#fontname   A path to the TrueType (.ttf) font file or a font pattern.
	#ptsize     The desired point size (may be fractional)
	#angle      The rotation angle, in radians (positive values rotate counter clockwise)
	#x,y        X and Y coordinates to start drawing the string
	#string     The string itself
	
	#@bounds = $image->stringFT($fgcolor,$fontname,$ptsize,$angle,$x,$y,$string,\%options) 
	
	#my @bounds = $image->stringFT(_color('0,0,0'),$ttf,10,0,0,0,$str,{}) 
	my $pt = $apt||6;
	my $pad = 0;
	#print STDERR "just = $just_bounds\n";
	my @bounds = GD::Image->stringFT(0,$ttf,$pt,$angle,0,0,$str,{}); 
	my ($w,$h) = @bounds[2,3];
	$h = $pt if $h == 0;
	if($just_bounds)
	{
		return ($w,$h);
	}
	
	#print "\"$str\": old pos: $x,$y, size: $w,$h\n";
	if (($right_flag==-1?$x:($right_flag==0?$x+$w/2:$x+$w))+$pad > $width)
	{
#		$x = $right_flag == -1 ? $width-$w-$pad : ($right_flag == 0 ? $width - $w/2 - $pad : $width-$pad);
	}
	
	if($y+$h+$pad > $height)
	{
#		$y = $height-$w-$pad+$pt;
	}
	
	if($y < $pad)
	{
#		$y = $pad; 
	}
	
	if(($right_flag ==-1 ? $x : ($right_flag == 0 ? $x-$w/2 : $x-$w)) < $pad)
	{
#		$x = $right_flag == -1? $pad + $w : ($right_flag == 0 ? $pad +$w/2 : $pad );
	}
	if($x eq 'center')
	{
		$x = $width /2 - $w/2;
	}
	if($x eq 'right')
	{
		$x = $width - $w - $hash{xpad};
	}
	if($y eq 'center')
	{
		$y = $height/2-$h/2+$pt/2;
	}
	if($y eq 'bottom')
	{
		$y = $height-$h+$pt;
	}
	
	if($x_center)
	{
		$x = $x - $w/2;
	}
	
        my $neg = $apt/10;
        ($angle==90?$y:$x)-=$neg;
	#print "\"$str\": new pos: $x,$y\n";
	my $col = (0+($c||_color($img,'0,0,0')));
	
	#print STDERR " ***** using col[$col]\n";
	$img->stringFT($col,$ttf,$pt,$angle,$right_flag == -1 ? $x - $w : ( $right_flag == 0 ? $x - $w/2 : $x),$y+$pt,$str,{});
	
}
