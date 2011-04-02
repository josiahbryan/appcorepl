# Package: AppCore::Web::Common
# Common routines for Web modules, primarily of use is the load_template(), master_template(), error(), and get_full_url() functions.

package AppCore::Web::Common;
{
	
	use strict;
	use AppCore::Common;
	#use AppCore::Session;
	use Time::HiRes qw/time/;
	
	use CGI qw/:cgi/;
	use CGI::Cookie;
	
	use HTML::Entities;
	use HTML::Template;
	
	use constant ENABLE_FAKEHOSTS => 0;#$^O eq 'MSWin32' ? 0:1;
	use constant MAX_FAKEHOSTS => 10;
	
	
	require Exporter;
	use vars qw/@ISA @EXPORT/;
	@ISA = qw(Exporter);
	
	@EXPORT = qw/HTTP rpad get_full_url url_encode url_decode 
		escape unescape
		param Vars
		redirect getcookie setcookie 
		load_template master_template
		error
		encode_entities decode_entities/;
		
	push @EXPORT, @AppCore::Common::EXPORT;
	#push @EXPORT, @{ $CGI::EXPORT_TAGS{':cgi'} };
	
	sub simple_paging
	{
		shift if $_[0] eq __PACKAGE__;
		
		my ($count,$start,$length) = @_;
		
		return undef if !defined $count ;
		$length = 10 if !defined $length;
		$start  = 0  if !defined $start ;
		
		
		
		$start =~ s/[^\d]//g;
		
		$start = $count - $length if $start + $length > $count;
		$start = 0 if !$start || $start<0;
			
		return 
		{
			start		=> $start,
			length		=> $length,
			noun		=> 'Items',
			
			count 		=> $count,
			pages 		=> int($count / $length),
			cur_page 	=> int($start / $length) + 1,
			next_start 	=> $start + $length,
			prev_start 	=> $start - $length,
			is_end 		=> $start + $length == $count,
			is_start	=> $start <= 0,
			has_pages	=> $start + $length < $count || $start - $length > 0,
		};
	
	}
		
	
	sub get_full_url
	{
		return $ENV{SCRIPT_NAME}.$ENV{PATH_INFO}.($ENV{QUERY_STRING}?'?'.$ENV{QUERY_STRING}:'');
	}
	
	sub url_encode
	{
		local $_;
		$_=shift;s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;$_;
	}
	
	sub url_decode
	{
		shift if $_[0] eq __PACKAGE__;	
		$_=shift;s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;$_;
	}
	
	sub escape 
	{  
		#@_=($_) if !@_; 
		eval { s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg foreach @_; };
		if(defined wantarray) 
			{ return wantarray ? @_ : "@_" } 
		else 
			{ $_ = "@_" } 
	}
	
	sub unescape 
	{
		#@_=($_) if !@_; 
		eval { s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg foreach @_; };
		if(defined wantarray) 
			{ return wantarray ? @_ : "@_" } 
		else 
			{ $_ = "@_" } 
	}
	
	sub param
	{
		return AppCore::Common->context()->http_args()->{shift()};
	}
	
	sub Vars
	{
		return AppCore::Common->context()->http_args();
	}
	
	
	sub redirect
	{
		shift if $_[0] eq __PACKAGE__;
		my $url = shift;
	
		#print STDERR called_from().": ".__PACKAGE__."::redirect(): Redirecting to '$url'\n";
		AppCore::Session->save;
			
		#print STDERR "redirect mark1\n";
		# For FastCGI usage
 		if(AppCore::Common->context->{mod_fastcgi})
		{
			#print STDERR "redirect mark4\n";
			print "Status: 302 Moved Temporarily\r\n";
			
			my $cookies = AppCore::Common->context->x('http_raw_outgoing_cookie_cache') || {};
			if($cookies)
			{
				#print STDERR "redirect mark5\n";
				foreach my $name (keys %$cookies)
				{
					#print STDERR "Debug: Setting outgoing cookie '$name': '$cookies->{$name}'\n";
					print "Set-Cookie:".$cookies->{$name}."\r\n";
				}
			}
			print "Location: $url\r\n\r\n";
			
			goto END_HTTP_REQUEST;
		}
		# For any other regular CGI dispatcher
		else
		{
			#print STDERR "redirect mark6\n";
			print "Status: 302 Moved Temporarily\r\n";
			
			my $cookies = AppCore::Common->context->x('http_raw_outgoing_cookie_cache') || {};
			if($cookies)
			{
				#print STDERR "redirect mark6.1\n";
				foreach my $name (keys %$cookies)
				{
					#print STDERR "Debug: Setting outgoing cookie '$name': '$cookies->{$name}'\n";
					print "Set-Cookie:".$cookies->{$name}."\r\n";
				}
			}
			
			print "Location: $url\r\n\r\n";
			exit 0;
		}
		#print STDERR "redirect mark7\n";
	}
	
	my $modperl_cookie_fetch = undef;
	my $cgi_cookie_cache = {};
	sub getcookie
	{
		if(!AppCore::Common->context->{mod_fastcgi}) #$MOD_PERL)
		{
			my $name = shift;
			#$modperl_cookie_fetch = CGI::Cookie->fetch(Apache2::RequestUtil->request) if !$modperl_cookie_fetch;
			#my $c = $modperl_cookie_fetch->{$name};
			#print STDERR "Debug: getcookie($name) - got fetch hash as $c\n";
			#return $c ? $c->value : undef;
	
			#$ENV{HTTP_COOKIE} = 'requests.tf_form_vis=-1; eas.auth_ticket=jbryan%3Ad1262c8dc9171c394b413e7984291ef0; requests.type=2; requests.view=list; requests.filter_name=open; requests.sort_col=1';
			
			my $cache = AppCore::Common->context->x('http_cookie_cache');
			if(!$cache)
			{
				my $cookies = AppCore::Common->context->{httpd} ? AppCore::Common->context->{httpd}->header('cookie') : $ENV{HTTP_COOKIE};
				#print STDERR "Debug: getcookie(): Reading enviro HTTP_COOKIE: Cookies: $cookies\n";
				my @pairs = split/;\s*/, $cookies;
				
				my %cache_map = map { my @x = split/=/, $_; url_decode($x[0]) => url_decode($x[1]) } @pairs;
				
				$cache = \%cache_map;
				
				#print STDERR "COOKIES: ".Dumper $cache;
				
				AppCore::Common->context->x('http_cookie_cache', $cache);
			}
			
			return $cache->{$name};
			
			
		}
		else
		{	
			my $name = shift;
			my $cache = AppCore::Common->context->{'http_cookie_cache'};
			$cache = AppCore::Common->context->{'http_cookie_cache'} = {} if !$cache;
			
			$cache->{$name} = cookie($name) if !$cache->{$name};
			return $cache->{$name};
			#return $cgi_cookie_cache->{$_[0]} if $cgi_cookie_cache->{$_[0]};
			
		}
	}
	
	
	sub setcookie
	{
		my ($name,$value,$exp) = (shift,shift,shift||'+20y');
		#print STDERR "Set-Cookie:".cookie(-name => "$name", -value =>["$value"], -expires=>"$exp")."\n";
		if(AppCore::Common->context->{httpd})
		{
			AppCore::Common->context->{httpd}->setcookie($name,$value,$exp);
			AppCore::Common->context->x('http_cookie_cache',{}) if !AppCore::Common->context->x('http_cookie_cache');
			AppCore::Common->context->x('http_cookie_cache')->{$name} = $value;
		}
		else
		{
			#my $cookie = "Set-Cookie: ".url_encode($name)."=".url_encode($value)."; expires=$exp; path=/\n";
			#my $cookie = "Set-Cookie: ".$name."=".url_encode($value)."; expires=$exp; path=/\n";
			my $cookie = cookie(-name => "$name", -value =>["$value"], -expires=>"$exp",-path=>"/");
			print "Set-Cookie:".$cookie."\n";
			#print $cookie;
			#print STDERR called_from().": Setting cookie: $cookie\n";
			#$cgi_cookie_cache->{$name} = $value;
			AppCore::Common->context->x('http_cookie_cache',{}) if !AppCore::Common->context->x('http_cookie_cache');
			AppCore::Common->context->x('http_cookie_cache')->{$name} = $value;
			
			AppCore::Common->context->x('http_raw_outgoing_cookie_cache',{}) if !AppCore::Common->context->x('http_raw_outgoing_cookie_cache');
			AppCore::Common->context->x('http_raw_outgoing_cookie_cache')->{$name} = $cookie;
		}
# 		else
# 		{
# 			print "Set-Cookie:".cookie(-name => "$name", -value =>["$value"], -expires=>"$exp",-path=>"/")."\n";
# 			$cgi_cookie_cache->{$name} = $value;
# 		}
	}
	
	
	sub output
	{
		my $tmpl = shift;
		
		#$tmpl->param('user_'.$_ => $sid->{user_data}->{$_}) foreach keys %{$sid->{user_data}};
		#die Dumper $sid->{user_data};
		
		my $text = $tmpl->output;
		print "Content-Type: text/html\n\n";
		#$text =~ s/<\/body>/$urchin<\/body>/g;
		#$text =~ s/<img(.*?)src=['"]([^\'\"]+)['"](.*?)(?:jblog_auto_link=([^\s]+))?\/?>/_auto_link_image($1,$2,$3,$4,$5)/segi;
		print $text;
		exit;
	}
	
	
	
	sub error
	{
		my ($title,$error) = @_;
		
		if(UNIVERSAL::isa($error,'AppCore::Error'))
		{
			$title = $error->title;
			$error = $error->text;
		}
		
		if(ref $error)
		{
			$error = "<pre>".Dumper($error,@_)."</pre>";
		}
		
		#exit;
		
		print "Content-Type: text/html\r\n\r\n<html><head><title>$title</title></head><body><h1>$title</h1>$error<hr></body></html>\n";
		if(AppCore::Common->context->{mod_fastcgi})
		{
			goto END_HTTP_REQUEST;
		}
		else
		{
			exit -1;
		}
	}
	
	
	my $FAKE_HOSTCOUNT = 0;
	sub _http_host
	{
		my $host = shift;
		my $root = shift;
		$FAKE_HOSTCOUNT = 0 if ++ $FAKE_HOSTCOUNT >= MAX_FAKEHOSTS;
		my $new = "http://eas${FAKE_HOSTCOUNT}.".$host.$root;
		#print STDERR "new: $new\n";
		
		return $new;
	}
	
	sub _template_filter
	{
		my $textref = shift;
		my $tmpl = shift;
		
		$$textref =~ s/\%\%(.*?)\%\%/<TMPL_VAR NAME="$1">/gi;
		$$textref =~ s/\%(\/?)tmpl_(.*?)\%/<$1TMPL_$2>/gi;
		#$$textref =~ s/\%([^\s](?:.|\n)*?)%/_template_perl_eval($1,$+[1],$textref,$tmpl)/segi;
			
		my ($var_blob)	= $$textref =~ /<!--\[CSSVARS\]([^>]+)-->/si;
		if($var_blob)
		{
			my %pairs = $var_blob =~ /\s*([\w\d_]+):\s*(.*)\s*;.*/gi;
			#die Dumper \%pairs, $var_blob;
			$$textref =~ s/<\$([^\>]+)>/$pairs{$1}/gi;
		}
		
		
		if(ENABLE_FAKEHOSTS) # && $httpd)
		{
			my $root = AppCore::Common->context->eas_http_root;
			my $host = $ENV{HTTP_HOST};
			$host = 'web' if $host eq '10.0.1.6';
			$$textref =~ s/<tmpl_var eas_root>/_http_host($host,$root)/segi;
		}
		
		$$textref =~ s/<perl>((?:.|\n)*?)<\/perl>/_template_perl_eval($1,$+[1],$textref,$tmpl)/segi;
		
		#die Dumper $$textref;
		
		
		
	}
	
	# Context variables for perl eval 
	our $TMPL_FILE;
	our $TMPL;
	sub _template_perl_eval
	{
		my $code = shift;
		my $match_end = shift;
		my $tref = shift;
		my $tmpl = shift;
		#print STDERR "Got code: $code\n";
		
		my $out = eval($code);
		if($@)
		{
			my $err = $@;
			my $pre = substr($$tref,0,$match_end - length($code));
			my @lines = $pre =~ /(\n)/g;
			my $count = scalar @lines ;
			#print STDERR "\$count=$count,match_end=$match_end\n";
			$err =~ s/\(eval \d+\)\s+line\s*(\d+)/'line '.($count+$1)/segi;
			error("Error in $tmpl->{options}->{filepath} at &lt;perl&gt; at line ".($count+1).":","<pre>$err</pre><textarea rows=30 cols=60>$code</textarea>");
		}
		return $out;
	}
	
	sub load_template
	{
		my $file = shift;
		my $module = shift || undef;
		my $bless_pkg = shift || 'HTML::Template';
		$TMPL_FILE = $file;
		#AppCore::Common::print_stack_trace() if $pkg eq 'AppCore::Module::OMS::WebApp';
		my ($split_path,$split_file) = $file =~ /^(.*)\/([^\/]+)$/;
		#die Dumper $split_path,$split_file;
		my %args = (filename => $file,
			die_on_bad_params=>0,
			#cache_debug => 1, #,cache=>1);
			#file_cache_dir => '/tmp/',
			#file_cache => 1,
			filter	=> \&_template_filter,	
			search_path_on_include	=> 1,
			path	=> $split_path);
		use Data::Dumper;
		#print STDERR Dumper(\%args);
		my $tmpl = $bless_pkg->new(
			%args
		);
		
		#print STDERR MY_LINE(). "Debug: eas_http_root: ".AppCore::Common->context->eas_http_root." ($root)\n";	
		$tmpl->param(http_root => AppCore::Common->context()->http_root || '');
		$tmpl->param(http_bin  => AppCore::Common->context()->http_bin  || '');
		$tmpl->param(MAX_FAKEHOSTS    => MAX_FAKEHOSTS);
		$tmpl->param(ENABLE_FAKEHOSTS => ENABLE_FAKEHOSTS);
		
		my $host = $ENV{HTTP_HOST};
		# TODO add aliasing for backend servers back to front end
		$tmpl->param(HTTP_HOST        => $host);
		
		my $user = AppCore::Common->context->user;
		if(!$user)
		{
			eval 'require AppCore::AuthUtil';
			$user = AppCore::AuthUtil->authenticate;
		}
		if($user)
		{
			my $compref = $user->compref;
			if($compref)
			{
				$tmpl->param('user_' . $_ => $compref->get($_)) foreach $compref->columns;
			}
			$tmpl->param('user_' . $_ => $user->{$_}) foreach keys %$user;	
		}
		
		
		return $tmpl;
	
	
	}
	
	use Data::Dumper;
	sub HTTP 
	{
		#print STDERR Dumper \@_;
		my $code;
		if(@_ == 2)
		{
			$code = 200;
		}
		
		$code = shift if !$code;
		
	#	$code = 200; ### NO OTHER CODES SUPPORTED RIGHT NOW
		if($code == 200)
		{
			return ($code,@_);
		}
		elsif($code == 302)
		{
			return ($code,@_);
		}
		elsif($code == 404)
		{
			return ($code,@_);
		}
		elsif($code == 500)
		{
			return ($code,@_);
		}
		else
		{
			die "Invalid HTTP Code '$code'";
		}
	}
	
}
1;
