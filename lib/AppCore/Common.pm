# Package: AppCore::Common
# Common routines, EAS include path initalization, mysql schema updates, useful constants, and more.
BEGIN
{
	my $config = $ENV{APPCORE_CONFIG};
	#use AppCore::Config;
	if($config)
	{
		print STDERR "$0: Loading AppCore config from $config\n";
		eval('require "'.$config.'"');
		die "Error loading config: $@" if $@;
	}
	else
	{
		$config = 'AppCore::Config';
		print STDERR "$0: Loading DEFAULT AppCore config from $config\n";
		eval('use '.$config);
		die "Error loading config: $@" if $@;
	}
}

package AppCore::Common;
{
	
	use strict;
	
	use AppCore::RunContext;
	#use AppCore::EmailQueue;
	
	use Data::Dumper;
	use DateTime;
	
	require Exporter;
	use vars qw/@ISA @EXPORT/;
	@ISA = qw(Exporter);
	
	@EXPORT = qw/
		Dumper 
		context 
		
		pad 
		rpad 
		min 
		max
		commify
		trim_spaces 
		
		called_from 
		print_stack_trace
		 
		if_defined 
		is_print 
		inlist 
		in_acl_list
		peek
		 
		send_email
		
		date_math 
		stamp 
		nice_date 
		date 
		dt_date
		simple_duration_to_hours
		to_delta_string
		delta_minutes
		seconds_since
		iso_date_to_seconds
		pretty_timestamp
		approx_time_ago
		
		read_file 
		write_file
		
		parse_csv 
		
		taint_sql 
		taint_sys 
		taint_text 
		taint_number 
		taint
		
		guess_title
		
		MY_LINE
		SYS_PATH_BASE 
		SYS_PATH_MODULES
		SYS_PACKAGE_BASE
		
		timemark
		
		/;
		
	sub EMAILQUEUE_SPOOL_DIR { '/appcluster/var/spool/emailqueue' }
	
	sub SYS_PATH_BASE    { AppCore::Config->get("APPCORE_ROOT") }
	sub SYS_PATH_MODULES { SYS_PATH_BASE . '/modules' }
	sub SYS_PACKAGE_BASE { 'AppCore::Web::Module' }
	
	### Section: Bootstrap Library Paths
	# This adds the ./lib directory under each moduled to @INC so that
	# other modules can use packages defined by other modules without
	# having to prefix everything with EAS::Module::$modname::
	BEGIN 
	{
		#print STDERR "AppCore::Common: BEGIN 1\n";
		opendir(DIR, SYS_PATH_MODULES);
		map { unshift @INC, join '/', SYS_PATH_MODULES, $_, 'lib'; unshift @INC, join '/', SYS_PATH_MODULES, $_; } grep { !/^\./ } readdir DIR;
		closedir(DIR);
		unshift @INC, SYS_PATH_MODULES;
		#print STDERR "AppCore::Common: BEGIN 2\n";
	}

	my $GlobalContext;
	
	sub context
	{
		$GlobalContext = AppCore::RunContext->new if !$GlobalContext;
		return $GlobalContext;
	}
	
	sub MY_LINE() {my (undef,$f,$l) = caller(0);"[$f:$l] "}
	
	sub min{my($a,$b)=@_;$a<$b?$a:$b}
	sub max{my($a,$b)=@_;$a>$b?$a:$b}
	
	sub trim_spaces
	{
		shift if $_[0] eq __PACKAGE__;
		my $tmp = shift;
		$tmp =~ s/(^\s+|\s+$)//g;
		return $tmp;
	}
	
	sub nice_date
	{
		#return '' unless $_[0] ne '';
		$_[0] = date() if !$_[0];
		my ($date,$h1,$m1,$s1) = ($_[0]=~/^(.*\s)?(\d+):(\d+)\:(\d+)$/);
		my $a='am';
		if($h1>=12)
		{
			$h1-=12 if($h1 ne '12');
			$h1=rpad($h1);
			$a='pm';
			#$h1=~s/^0//g;
		}
		return "$date$h1:$m1:$s1 $a";
	}
	
	our %DurationConversion = qw/h 1 d 24 w 168 m 672 y 8760/;
	our %DurationNames = qw/h hours w weeks m months y years/;
		
	sub simple_duration_to_hours
	{
		my $dur = shift;
		my ($num,$unit) = $dur =~ /^(\.\d+|\d(?:\.\d+)?)\s*(\w)?\w*$/;
		
		my $ex = "Example: '4.5d' or '4.5 days'";
		if(!defined $num)
		{
			die "No number given in the duration. $ex";
		}
		elsif(!$unit)
		{
			warn "No unit given in '$dur', assuming hours";
			$unit = 'h';
		}
		elsif(!$DurationConversion{$unit})
		{
			die "Invalid unit of time '$unit' - valid units are: hours (h), days (d), weeks (w), months (m), or years (y). $ex";
		}
		
		my $dur_hours = $DurationConversion{$unit} * $num;
		
		#print STDERR "Converted '$dur' to $dur_hours hours\n";
		
		return $dur_hours;
		
	
	}
	
	sub to_delta_string
	{
		my $line = { min => shift };
		
		
		if($line->{min} > 60)
		{
			my $hr = int($line->{min}/60);
			$line->{min} =  ($line->{min} - $hr*60);
			$line->{hour} = $hr;
			$line->{hour_suffix} = ' hr'.($hr>1?'s':'').', ';
			
			if($line->{hour} > 24)
			{
				my $day = int($line->{hour} / 24);
				$line->{hour} = ($line->{hour} - $day*24);
				$line->{hour_suffix} = ' hr'.($line->{hour}>1?'s':'').', ';
				$line->{day} = $day;
				$line->{day_suffix} = ' day'.($day>1?'s':'').', ';
				
				if($line->{day} > 7)
				{
					my $week = int($line->{day} / 7);
					$line->{day} = ($line->{day} - $week*7);
					$line->{day_suffix} = ' day'.($line->{day}>1?'s':'').', ';
					$line->{week} = $week;
					$line->{week_suffix} = ' week'.($week>1?'s':'').', ';
					
					if($line->{week} > 4)
					{
						my $month = int($line->{week} / 4);
						$line->{week} = ($line->{week} - $month*4);
						$line->{week_suffix} = ' week'.($line->{week}>1?'s':'').', ';
						$line->{month} = $month;
						$line->{month_suffix} = ' month'.($month>1?'s':'').', ';
						
						if($line->{month} > 12)
						{
							my $year = int($line->{month} / 12);
							$line->{month} = ($line->{month} - $year*12);
							$line->{month_suffix} = ' month'.($line->{month}>1?'s':'').', ';
							$line->{year} = $year;
							$line->{year_suffix} = ' year'.($year>1?'s':'').', ';
						}
					}
				}
			}
		}
		
		my @ago;
		foreach my $key (qw/year month week day hour/)
		{
			push @ago, $line->{$key}.$line->{$key.'_suffix'} if $line->{$key};
		}
		
		push @ago, int($line->{min}).' min';
		
		return join '', @ago;
	}
	
	
	sub dt_date
	{
		my $date = shift || date();
		my ($y,$m,$d,$h,$mn,$s) = split/[-\s:]/, $date;
		my %args;
		$args{year} = $y if $y;
		$args{month} = $m if $m;
		$args{day} = $d if $d;
		$args{hour} = $h if $h;
		$args{minute} = $mn if $mn;
		$args{second} = $s if $s;
		
		return DateTime->new(%args);
	}
	
	sub date #{ my $d = `date`; chomp $d; $d=~s/[\r\n]//g; $d; };
	{
		if(@_ == 1) { @_ = (epoch=>shift) }
		my %args = @_;
		my $x = $args{epoch}||time;
		my $ty = ((localtime($x))[5] + 1900);
		my $tm =  (localtime($x))[4] + 1;
		my $td = ((localtime($x))[3]);
		my ($sec,$min,$hour) = localtime($x);
		my $date = "$ty-".rpad($tm).'-'.rpad($td);
		my $time = rpad($hour).':'.rpad($min).':'.rpad($sec);
		
		#shift() ? $time : "$date $time";
		if($args{small})
		{
			my $a = 'a';
			if($hour>12)
			{
				$hour -= 12;
				$a = 'p';
				
				$hour = 12 if $hour == 0;
			}
			return int($tm).'/'.int($td).' '.int($hour).':'.rpad($min).$a;
		}
		else
		{
			return $args{array} ? ($date,$time) : "$date $time";
		}
	}
	
	
	# Since learning more perl, I found I probably
	# could do '$_[0].=$_[1]x$_[2]' but I havn't gotten
	# around to changing (and testing) this code.
	sub pad
	{
		shift if $_[0] eq __PACKAGE__;
		local $_ = if_defined(shift,'');
		my $len = shift || 8;
		my $chr = shift || ' ';
		$_.=$chr while length()<$len;
		$_;
	}
	
	sub rpad
	{
		shift if $_[0] eq __PACKAGE__;
		local $_ = if_defined(shift , '');
		my $len = shift || 2;
		my $chr = shift || '0';
		$_=$chr.$_ while length()<$len;
		$_;
	}
	sub called_from
	{
		shift if $_[0] eq __PACKAGE__;
		my $short = shift || 0;
		my ($package, $filename,$line) = caller(1);
		#my (undef,undef,$line) = caller(1);
		my (undef,undef,undef,$subroutine) = caller(2);
		
		if($short)
		{
			$filename =~ s/^.*\/([^\/]+)/$1/;
		}
	
		"$filename:$line / $subroutine()";
	}
	
	sub get_stack_trace
	{
		my $offset = 1+(shift||0);
		my $str = ""; #"Stack Trace (Offset: $offset):";
		for(my $x=0;$x<100;$x++)
		{
			#$tmp=(caller($x))[1];
			my ($package, $filename, $line, $subroutine, $hasargs,
				$wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($x+$offset);
			(undef,undef,undef, $subroutine, $hasargs,
				$wantarray, $evaltext, $is_require, $hints, $bitmask) = caller($x+$offset+1);
			#print "$x:Base[1]='$tmp' ($package:$line:$subroutine)\n";
			
			if($filename && $filename ne '')
			{
				#print STDERR "\t$x: Called from $filename:$line".($subroutine?" in $subroutine":"")."\n";
				$str .= "\t$x: Called from $filename:$line".($subroutine?" in $subroutine":"")."\n";
			}
			else
			{
				return $str;
			}
		}
		return $str;
	}
	
	sub print_stack_trace
	{
		my $x = shift;
		my $st = get_stack_trace($x+1);
		print STDERR $st;
		return $st;
		
	}
	sub if_defined { foreach(@_) { return $_ if defined } }
	
	sub is_print($)
	{
		local $_ = ord shift ;
		return $_ >= 32 && $_ < 126;
	}
	
	sub peek{$_[$#_]}
	
	sub inlist
	{
		my $val = shift;
		my $listref = shift;
		
		return undef if !defined $val;
		
		foreach my $item (@$listref)
		{
			return 1 if $item && $val && $item eq $val;
		}
		return 0;
	}
	
	
	sub in_acl_list
	{
		my $val = shift;
		my $valtype = shift || 'empid';
		my $list = shift;
		
		my $g = $valtype eq 'group' ? 1:0;
		
		return undef if !defined $val;
		
		local $_;
		foreach (@$list)
		{
			return 1 if $g ? /^\@$val$/ : $_ eq $val;
		}
		return 0;
	}
	
	
	# create timestamp down to the second (fmt: YYYY-MM-DD HH:MM:SS)
	sub stamp 
	{
		my $ty = ((localtime)[5] + 1900);
		my $tm =  (localtime)[4] + 1;
		my $td = ((localtime)[3]);
		my ($sec,$min,$hour) = localtime;
		my $date = "$ty-".rpad($tm).'-'.rpad($td);
		my $time = rpad($hour).':'.rpad($min).':'.rpad($sec);
		return "$date $time";
	}
	
	sub commify 
	{
		local $_  = shift;
		1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
		return $_;
	}
	
	
	sub parse_csv 
	{
	my $text = shift;      # record containing comma-separated values
	my @new  = ();
	push(@new, $+) while $text =~ m{
		# the first part groups the phrase inside the quotes.
		# see explanation of this pattern in MRE
		"([^\"\\]*(?:\\.[^\"\\]*)*)",?
		|  ([^,]+),?
		| ,
	}gx;
	push(@new, undef) if substr($text, -1,1) eq ',';
	return @new;      # list of values that were comma-separated
	} 
	
	
	sub date_math 
	{
		my ($date,$days) = @_;
			
		eval 'use DateTime';
		my ($y,$m,$d) = ( $date =~ /(\d\d\d\d)-(\d\d)-(\d\d)/);
		my $old = new DateTime(month=>$m,day=>$d,year=>$y);
		my $n = undef;
		$days = -($old->day_of_week) if $days == 0; # find week start
		if($days>0)
		{
			return $old->add( days => $days )->ymd;
		}
		else
		{
			return $old->subtract( days => -($days) )->ymd;
		}
	}
	
	
	
	
	sub send_email
	{
		#my ($list,$subject,$text,$high_import_flag,$from) = @_;
		shift;
		
		# Doesn't actually transmit - the transmit() method is called from bin/emailqueue.pl
		eval 'use AppCore::EmailQueue'; 
		AppCore::EmailQueue->send_email(@_);

	}
	
	
	sub delta_minutes
	{
		eval 'use DateTime';
		
		my $test = shift;
		my $test2 = shift || undef;
		my ($a,$b,$c,$d,$e,$f) = $test=~/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/;
		
		
		my $then = DateTime->new(year=>$a,month=>$b,day=>$c,hour=>$d,minute=>$e,second=>$f,time_zone=>'UTC');
		#$then->add(hours=>6);
		
		# how many minutes from $test to NOW ?
		my $dt;
		# = DateTime->now();
		if(!defined $test2)
		{
			$dt = DateTime->now();
			$dt->subtract(hours=>5);
		}
		else
		{
			my ($a,$b,$c,$d,$e,$f) = $test2=~/(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/;	
			$dt = DateTime->new(year=>$a,month=>$b,day=>$c,hour=>$d,minute=>$e,second=>$f,time_zone=>'UTC');
		}
		
		my $res = $dt->subtract_datetime_absolute($then);
		return $res->delta_seconds / 60;
	}
		
	sub pretty_timestamp
	{
		my $time = shift;
		my @x = $time =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/;
		
		my $h = $x[3];
		my $a = 'am';
		if($h >= 12)
		{
			$h -= 12;
			$h = 12 if $h == 0;
			$a = 'pm';
		}
		
		my $yr = substr($x[0],2,2);
		
		return "$x[1]/$x[2]/$yr ".($h<10?($h+0):$h).":$x[4]$a";
	}
	
	sub _unit_divide_if($$$$)
	{ 
		my ($new_unit,$val,$x,$unit) = @_; 
		if($$x>$val)
		{
			#print STDERR "$$x>$val ...\n";
			$$x /= $val;
			$$unit = $new_unit;
			
			# De-plural if it will round out to "1"
			$$unit =~ s/s$// if $$x > 0 && $$x < 2;
			
			
			#print STDERR "...down to $$x $$unit ---\n";
			return 0;
		}
		else
		{
			#print STDERR "$$x<$val $new_unit, still $$x $$unit /\n";
			return 1;
		} 
	}
	
	sub approx_time_ago
	{
		my $date = shift;
		my $x = seconds_since($date);
		my $orig = $x;
		#print STDERR "[$orig] Start, x=$x\n";
		my $unit = $x > 0 && $x < 2 ? 'second' : 'seconds';
		goto _approx_time_ago_end if _unit_divide_if('minutes',	60,	\$x, \$unit);
		goto _approx_time_ago_end if _unit_divide_if('hours',	60,	\$x, \$unit);
		goto _approx_time_ago_end if _unit_divide_if('days',	24,	\$x, \$unit);
		goto _approx_time_ago_end if _unit_divide_if('months',	365/12,	\$x, \$unit);
		goto _approx_time_ago_end if _unit_divide_if('years',	12,	\$x, \$unit);
# 		goto _approx_time_ago_end if _unit_divide_if('centuries',	100,		\$x, \$unit);
# 		goto _approx_time_ago_end if _unit_divide_if('millenia',	1000,		\$x, \$unit);
# 		goto _approx_time_ago_end if _unit_divide_if('eons',	100,		$x, $unit);
		_approx_time_ago_end:
		$x += 0.5 if $x - int($x) >= 0.5; 
		$x = int($x); # remove decimals
		#print STDERR "[$orig] Done, returning $x $unit\n";
		return wantarray ? ($x,$unit) : "$x $unit";
		
	}
	
	use POSIX;
	sub seconds_since
	{ 
		shift if $_[0] eq __PACKAGE__;
		my $previous_timestamp = shift;
		return iso_date_to_seconds(date()) - iso_date_to_seconds($previous_timestamp);
	}
	sub iso_date_to_seconds
	{
		shift if $_[0] eq __PACKAGE__;
		my $datetime = shift;
	
		my @dash = split(/-/, $datetime);
		my $year = $dash[0];
		$year = $year - 1900;
		my $mon = $dash[1];
		$mon = $mon - 1;
		my @space = split(/ /,$dash[2]);
		my $day = $space[0];
		my @col = split(/:/, $space[1]);
		my $hour = $col[0];
		$hour = $hour - 1;
		my $min = $col[1];
		my $sec = $col[2];
		my $wday = 0;
		my $yday = 0;
	
		my $unixtime = mktime ($sec, $min, $hour, $day, $mon, $year, $wday, $yday);
		return $unixtime;
	}
	
	
	sub taint_sql
	{
		my $val = shift;
		#$val=~s/(\binsert\b|\bdrop\b|\bdelete\b|\bcreate\b|\bupdate\b|\bselect\b|;)//ig; # basic protection
		$val=~s/(;)//ig; # basic protection
		$val=~s/\\//g; # remove '\' from the string
		$val=~s/(['"])/\\$1/g; # escape ' and "
		$val=~s/(^\s|\s$)//g; # remove spaces at beginnning/end
		return $val;
	}
	
	sub taint_text
	{
		my $val = shift;
		$val =~ s/[^\w\d\_\-\.\!\@\#\$\%\^&*\(\)\'\"\[\]\_\=\+\`\~\,\/\?\:\;\{\}\|\\\s]//g;
		return $val;
	}
	
	
	sub taint
	{
		my $val = shift;
		my $reg = shift;
		
		$reg = '[^\d]+' if $reg eq '\d';
		
		$val =~ s/^$reg$//g;
		return $val;
	}
	
	sub taint_number
	{
		my $val = shift;
		$val =~ s/^[^-+\d\.]+$//g;
		return $val;
	}
	
	
	
	
	# Function: guess_title($name)
	# Static - guess the title for $name. E.g. converts foo_bar or FooBar to 'Foo Bar', quoteestid or quoteest to 'Quote Est.' and a few other minor optimizations.
	my %TITLE_CACHE;
	sub guess_title#($name)
	{
		shift if $_[0] eq __PACKAGE__;
		my $name = shift;
		return $TITLE_CACHE{$name} if defined $TITLE_CACHE{$name};
		my $oname = $name;
		$name =~ s/([a-z])([A-Z])/$1 $2/g;
		$name =~ s/([a-z])_([a-z])/$1.' '.uc($2)/segi;
		$name =~ s/^([a-z])/uc($1)/seg;
		$name =~ s/\/([a-z])/'\/'.uc($1)/seg;
		$name =~ s/\s([a-z])/' '.uc($1)/seg;
		$name =~ s/\s(of|the|and|a)\s/' '.lc($1).' '/segi;
		$name .= '?' if $name =~ /^is/i;
		$name =~ s/id$//gi;
		my $chr = '#';
		$name =~ s/num$/$chr/gi; 
		$name =~ s/datetime$/Date\/Time/gi;
		$name =~ s/\best\b/Est./gi;
		
		$TITLE_CACHE{$oname} =  $name;
		#s/id$//g;
		#s/[_-]/ /g;
		#s/\best\b/est./g;
		#s/(^\w|\s\w)/uc($1)/segi;
		
		return $name;
	}
	
	my $uniqueid_counter = 0;
	sub uniqueid { return 'id'.time().($uniqueid_counter++) }
	
	
	sub changes_to_html
	{
		shift if $_[0] eq __PACKAGE__;
		my $ref = shift;
		my %changes = %{ shift || {} };
		my @keys = keys %changes;
		my $col;
		my @out = map {
			$col = $_;
			my $title = $ref->field_meta($col);
			if($title && $title->{linked} && eval '$ref->get($col)->can("stringify")') 
			{
				$changes{$col} = $ref->get($col)->stringify;
			}
			else
			{
				
			}
			#print STDERR "Debug: col($col),title(".($title?$title:'(undef)')."),linked(".($title?$title->{linked}:'(undef)')."): changes($changes{$col})\n";
			
			$title = $title ? ($title->{title} ? $title->{title} : AppCore::Common::guess_title($col)) : AppCore::Common::guess_title($col);
			"<span class='field_title'>$title</span> ". 
				($title=~/to$/i ? "" : "to ").
				'"<span class="field_value">'.(ref $changes{$col} && eval '$changes{$col}->can("stringify")' ? $changes{$col}->stringify : $changes{$col}).'</span>"'
		} @keys;
		@out = grep {$_} @out;
		my $str = @out > 2 ? (join(', ', @out[0..$#out-1]).', and '.$out[$#out]) : join(' and ',@out);
		
		return $str;
	}
	
	sub read_file
	{
		shift if $_[0] eq __PACKAGE__;
		my $file = shift;
		open(FILE,"<$file") || die "Cannot open $file for reading: $!";
		my @buffer = <FILE>;
		close(FILE);
		return join '', @buffer;
	}
	
	
	sub write_file
	{
		shift if $_[0] eq __PACKAGE__;
		my $file = shift;
		open(FILE,">$file") || die "Cannot open $file for writing: $!";
		print FILE join '', @_;
		close(FILE);
	}
	
	use Time::HiRes qw/time/;
	our $LastTime = 0;
	our $TimeSum;
	sub timemark
	{
		my $title = shift;
		if(!$LastTime)
		{
			#print STDERR "[TIME MARK] START\n";
			$TimeSum = 0;
		}
		else
		{
			my $diff = time - $LastTime;
			$TimeSum += $diff;
			print STDERR "[TIME MARK] ".sprintf('%04d',int($diff * 1000))."ms (".sprintf('%04d',int($TimeSum* 1000))."ms total) ".($title?" - $title":"")." at ".called_from(1)."\n";
		}
		
		$LastTime = time;
	}
	
};

package DateTime;
{
	sub datetime
	{
		my $self = shift;
		my $sep = shift || ' ';
		return $self->ymd('-').$sep.$self->hms(':');
	}
}
1;
