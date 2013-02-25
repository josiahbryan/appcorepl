# Package: AppCore::Web::Common
# Common routines for Web modules, primarily of use is the load_template(), error(), and get_full_url() functions.

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
	
	require Exporter;
	use vars qw/@ISA @EXPORT/;
	@ISA = qw(Exporter);
	
	@EXPORT = qw/HTTP get_full_url url_encode url_decode 
		escape unescape
		param Vars
		redirect getcookie setcookie 
		load_template
		error
		encode_entities decode_entities
		clean_html
		html2text
		text2html
		might_be_html
		tmpl_select_list
		/;
		
	push @EXPORT, @AppCore::Common::EXPORT;
	#push @EXPORT, @{ $CGI::EXPORT_TAGS{':cgi'} };
	
	sub tmpl_select_list
	{
		shift if $_[0] eq __PACKAGE__;
		my $curid = shift;
		my $data  = shift;
		
		my @all;
		if(!ref $data && $data =~ /^enum\((.*?)\)$/i)
		{
			@all = $1 =~ /'([^"]+?)'/g;
		}
		else
		{
			@all = @{$data || []};
		}
		
		my $include_invalid = shift || 0;
		
		my @list;
		if($include_invalid)
		{
			push @list, { 
				value 		=> undef,
				text		=> '(None)',
				selected	=> !$curid,
			};
		}
		
		foreach my $item (@all)
		{
			if(ref $item eq 'HASH')
			{
				push @list, {
					value	=> $item->{value} || $item->{id},
					text	=> $item->{text}  || $item->{display},
					selected => defined $curid && ($item->{value} || $item->{id}) eq $curid,
				}
			}
			else
			{
				
				push @list, {
					value	=> $item,
					text	=> $item,
					selected => defined $curid && $item eq $curid,
				}
			}
		}
		#print STDERR "list: ".Dumper(\@list);
		return \@list;
	}
	
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
		shift if $_[0] eq __PACKAGE__;
		local $_;
		$_=shift;s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;$_;
	}
	
	sub url_decode
	{
		shift if $_[0] eq __PACKAGE__;
		local $_;	
		$_=shift;s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;$_;
	}
	
	sub escape 
	{  
		#@_=($_) if !@_;
		shift if $_[0] eq __PACKAGE__;
		local $_; 
		eval { s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg foreach @_; };
		if(defined wantarray) 
			{ return wantarray ? @_ : "@_" } 
		else 
			{ $_ = "@_" } 
	}
	
	sub unescape 
	{
		shift if $_[0] eq __PACKAGE__;
		local $_;
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
		my $expires_config = shift;
	
		print STDERR called_from().": ".__PACKAGE__."::redirect(): Redirecting to '$url'\n";
		#AppCore::Session->save;
			
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
			
			my $expires = undef;
			if($expires_config)
			{
				my $dt = DateTime->now();#timezone => 'America/Chicago');
				$dt->add( days => $expires_config->{days} || 31 );
				# Expires: Thu, 01 Dec 1994 16:00:00 GMT
				$expires = "Expires: ".$dt->strftime("%a, %d %b %Y %H:%M:%S +000")."\r\n";
							  #%a, %d %b %Y %H:%M:%S +0000

			}
			
			print "Location: $url\r\n$expires\r\n";
			
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

		#$text = Encode::_utf8_on($text);
                #$text =~ s/\pM*//g; # remove wideprints
		#$text= "foobar";

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
		
		#print STDERR "$title: ".html2text($error);
		print STDERR "[".(AppCore::Common->context->user ? AppCore::Common->context->user->user."@" : "").$ENV{REMOTE_ADDR}."] ".get_full_url()." $title: ".html2text($error)."\n";
		
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
	
	sub _template_filter
	{
		my $textref = shift;
		#my $tmpl = shift || $HTML::Template::DelayedLoading::CurrentObject;
		
		#print STDERR "_template_filter: tmpl: '$tmpl', text: ".$$textref."\n";
		
		$$textref =~ s/\${inc:([^\}]+)}/get_included_file($1)/segi;
		#$$textref =~ s/\${if:([^\}]+)}/_rewrite_if_macro($1)/segi;
		#$$textref =~ s/\${(end|\/)if}/<\/tmpl_if>/gi;
		
		if(AppCore::Config->get("ENABLE_TMPL2JQ_MACRO"))
		{
			$$textref =~ s/\${tmpl2jq:([^\}]+)}/_tmpl2jq($1)/segi;
		}
		
		
		$$textref =~ s/<tmpl_if ([^>]+)>/_rewrite_if_macro($1)/segi;
		
		$$textref =~ s/\%\%(.*?)\%\%/<TMPL_VAR NAME="$1">/gi;
		$$textref =~ s/\%(\/?)tmpl_(.*?)\%/<$1TMPL_$2>/gi;
		#$$textref =~ s/\%([^\s](?:.|\n)*?)%/_template_perl_eval($1,$+[1],$textref,$tmpl)/segi;
			
# 		my ($var_blob)	= $$textref =~ /<!--\[CSSVARS\]([^>]+)-->/si;
# 		if($var_blob)
# 		{
# 			my %pairs = $var_blob =~ /\s*([\w\d_]+):\s*(.*)\s*;.*/gi;
# 			#die Dumper \%pairs, $var_blob;
# 			$$textref =~ s/<\$([^\>]+)>/$pairs{$1}/gi;
# 		}
		
		#$$textref =~ s/<perl>((?:.|\n)*?)<\/perl>/_template_perl_eval($1,$+[1],$textref,$tmpl)/segi;
		
		#die Dumper $$textref;
	}
	
	sub _tmpl2jq
	{
		my $file = shift;
		my $tmpl = shift || $HTML::Template::DelayedLoading::CurrentObject;
		my $block = AppCore::Web::Common->get_included_file($file,0,$tmpl);
		#$block =~ s/<tmpl_if ([^>]+?)>/{{if $1}}/segi;
		$block =~ s/<tmpl_if ([^>]*?)>/_rewrite_if_macro2($1,$block)/segi;
		$block =~ s/<\/tmpl_if>/{{\/if}}/gi;
		$block =~ s/<tmpl_unless ([^>]+?)>/_rewrite_if_macro2($1,$block,1)/segi;
		$block =~ s/<\/tmpl_unless>/{{\/if}}/gi;
		$block =~ s/<tmpl_loop ([^>]+?)>/{{each $1}}/gi;
		$block =~ s/<\/tmpl_loop>/{{\/each}}/gi;
		$block =~ s/<tmpl_else>/{{else}}/gi;
		$block =~ s/<tmpl_var ([^>]+)>/$tmpl->param($1)/segi if $tmpl;
		$block =~ s/%%(.+?html)%%/{{html $1}}/g;
		$block =~ s/%%([^\%]+)%%/\${$1}/g;

		#print STDERR "Final block: $block\n";
		
		return $block;
	}
	
	sub _rewrite_if_macro2
	{
		my $data = shift;
		my $block = shift;
		my $unless = shift;
		
		my ($var,$typecast) = $data =~ /^([^:]+)(?:\:(.*))?/;
		
		$typecast = lc $typecast;
		$typecast = 'list' if $block =~ /<tmpl_loop $var>/;
		
		# Adding 'this.' to the start of $var prevents errors when variables dont exist the dataset given to the template but are referenced in the template markup 
		
		if(!$typecast || $typecast eq 'num')
		{
			return $unless ? "{{if this.data?this.data.$var<=0:$var<=0}}" : "{{if this.data?this.data.$var>0:$var>0}}";
		}
		elsif($typecast eq 'str')
		{
			#return $unless ? "{{if this.data?!this.data.$var:1}}" : "{{if this.data?!!this.data.$var:0)}}";
			return $unless ? "{{if this.data?!this.data.$var:!$var}}" : "{{if this.data?!!this.data.$var:$var}}";
		}
		elsif($typecast eq 'list')
		{
			#return "{{if ".($unless?"!":"")."($var.length)}}";
			return $unless ? "{{if this.data?$var.length<=0:$var.length<=0}}" : "{{if this.data?this.data.$var.length:$var.length}}";
		}
	}
	
	
	
	
	sub _rewrite_if_macro
	{
		my $data = shift;
		my ($var,$typecast) = $data =~ /^([^:]+)(?:\:(.*))?/;
		return "<tmpl_if $var>";
	}
	
	
	my %FileCache;
	sub get_included_file
	{
		shift if $_[0] eq __PACKAGE__;
		my $file = shift;
		my $level = shift || 0;
		my $tmpl = shift || $HTML::Template::DelayedLoading::CurrentObject;
		my $orig = $file; 
		#return $FileCache{$orig} if $FileCache{$orig};
		use Data::Dumper;
		
		# Always properly replace %%appcore%% regardless of the variable defenition in the $tmpl
		my $www_root = AppCore::Config->get("WWW_ROOT");
		$file =~ s/%%appcore%%/$www_root/gi;
		
		# Handle arbitrary variable replacements in the filename
		$file =~ s/%%([^\%]+)%%/$tmpl->param($1)/segi if $tmpl && $file =~ /%%/;
		
		# Intelligently prepend the document root if this is an absolute filename relative to $WWW_DOC_ROOT
		if($file =~ /^\/appcore/i)
		{
			$file = AppCore::Config->get("WWW_DOC_ROOT") . $file;
		}
		
		if($tmpl && !-f $file)
		{
			my $test = join('/', $tmpl->{pargs}->{path}, $file);
			$file = $test if -f $test;
		}
		
		#if($file =~ /^%%[^\%]+%%$/)
		
		#print STDERR "get_included_file: file: '$file'\n";
		my $data = undef;
		if(-f $file)
		{
			$data = AppCore::Common->read_file($file);
			
			# Limit to 10 levels of includes
			if($data =~ /\${inc:/i && ++ $level < 10)
			{
				$data =~ s/\${inc:([^\}]+)}/get_included_file($1,$level)/segi;
			}	
		}
		else
		{
			#print STDERR Dumper $tmpl; 
			print STDERR __PACKAGE__."::get_included_file(): File does not exist: '$file'\n" if $file;
		
			$data = "";
		}
		
		$FileCache{$orig} = $data;
		
		return $data;
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
		#my $module = shift || undef;
		#my $bless_pkg = shift || 'HTML::Template::RetrievableParameters';
		$TMPL_FILE = $file;
		#AppCore::Common::print_stack_trace() if $pkg eq 'AppCore::Module::OMS::WebApp';
		my ($split_path,$split_file) = $file =~ /^(.*)\/([^\/]+)$/;
		#die Dumper $split_path,$split_file;
		
		# Assume $file is a filename if no spaces found
		#die "File doesn't exist: $file" if !-f $file && index($file,' ') < 0;
		warn "File doesn't exist: $file" && return undef if !-f $file && index($file,' ') < 0;
		 
		my %args;
		
		#print STDERR "load_template: $file\n";
		
		if(-f $file)
		{
			%args = (filename => $file,
				die_on_bad_params=>0,
				#cache_debug => 1, #,cache=>1);
				#file_cache_dir => '/tmp/',
				#file_cache => 1,
				filter	=> \&_template_filter,	
				search_path_on_include	=> 1,
				path	=> $split_path);
		}
		else
		{
			%args = (scalarref => \$file,
				die_on_bad_params=>0,
				filter	=> \&_template_filter);
			
		}
		
		use Data::Dumper;
		#print STDERR Dumper(\%args);
		my $tmpl = HTML::Template::DelayedLoading->new(
			%args
		);
		
		#print STDERR MY_LINE(). "Debug: eas_http_root: ".AppCore::Common->context->eas_http_root." ($root)\n";	
		$tmpl->param(http_root => AppCore::Common->context()->http_root || '');
		$tmpl->param(http_bin  => AppCore::Common->context()->http_bin  || '');
		
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
# 			my $compref = $user->compref;
# 			if($compref)
# 			{
# 				$tmpl->param('user_' . $_ => $compref->get($_)) foreach $compref->columns;
# 			}
			$tmpl->param('user_' . $_ => $user->{$_}) foreach keys %$user;	
		}
		
		
		return $tmpl;
	
	
	}
	
	use Data::Dumper;
# 	sub HTTP 
# 	{
# 		#print STDERR Dumper \@_;
# 		my $code;
# 		if(@_ == 2)
# 		{
# 			$code = 200;
# 		}
# 		
# 		$code = shift if !$code;
# 		
# 	#	$code = 200; ### NO OTHER CODES SUPPORTED RIGHT NOW
# 		if($code == 200)
# 		{
# 			return ($code,@_);
# 		}
# 		elsif($code == 302)
# 		{
# 			return ($code,@_);
# 		}
# 		elsif($code == 404)
# 		{
# 			return ($code,@_);
# 		}
# 		elsif($code == 500)
# 		{
# 			return ($code,@_);
# 		}
# 		else
# 		{
# 			die "Invalid HTTP Code '$code'";
# 		}
# 	}
	
	our $StopwordOrRegex;
	our @StopwordList;
	our %StopwordMap;
	
	sub init_stopwords
	{
		if(!@StopwordList)
		{
			@StopwordList = split /\n/, AppCore::Common->read_file(AppCore::Config->get('STOPWORDS_FILE') || 'conf/stopwords.txt');
			
			%StopwordMap = map { lc $_ => 1 } @StopwordList;
			 
			$StopwordOrRegex = '(' . join('\b|\b', @StopwordList).')';
		}
		
		
	}
	
	sub remove_stopwords
	{
		shift if $_[0] eq __PACKAGE__;
		init_stopwords();
		
		my $text = shift;
		if(ref $text)
		{
			$$text =~ s/$StopwordOrRegex//g;
		}
		else
		{
			$text =~ s/$StopwordOrRegex//g;
			return $text;
		}
	}
	
	sub html2text
	{
		shift if $_[0] eq __PACKAGE__;
		my $html = shift;
		$html =~ s/<p>\s*\n\s*(\w)/$1/g;
		$html =~ s/<(script|style)[^\>]*?>(.|\n)*?<\/(script|style)>//g;
		$html =~ s/<!--(.|\n)*?-->//g;
		$html =~ s/<br>([^\n])/<br>\n$1/gi;
		$html =~ s/(<\/(p|div|blockquote)>)/\n/gi;
		$html =~ s/<\/li><li>/, /g;
		$html =~ s/<li>/ * /g;
		$html =~ s/<[^\>]+>//g;
		$html =~ s/&amp;/&/g;
		$html =~ s/&nbsp;/ /g;
		$html =~ s/&quot;/"/g;
		$html =~ s/&mdash;/--/g;
		$html =~ s/&rsquo;/'/g;
		$html =~ s/&[lr]dquo;/"/g;
		$html =~ s/&hellip;/.../g;
		## template-specific codes
		$html =~ s/\%\%(.*?)\%\%//gi;
		$html =~ s/\%(\/?)tmpl_(.*?)\%//gi;
		$html =~ s/\%([^\d\s\'](?:.|\n)*?)%//gi;
		$html =~ s/—/ - /g;
		$html =~ s/’/'/g;
		$html =~ s/“/"/g;
		$html =~ s/”/"/g;
		# Textify some entitites
		$html =~ s/&#39;/'/g;
		$html =~ s/&#8217;/'/sg;
		$html =~ s/&#8230;/.../sg;
		$html =~ s/&#8211;/ - /sg;
		$html =~ s/&amp;#8217;/'/sg;
		$html =~ s/&#8220;/"/sg;
		$html =~ s/&#8221;/"/sg;
		
		
		#Remove Wordpress Scribd 'tag', Sample: [scribd id=64192688 key=key-uwgseze2p7s03ow8a8b mode=list]
		#$html =~ s/\[scribd[^\]]+\]/(Embedded Document from Scribd)/gi;
		$html =~ s/\[scribd id=([^\s]+) key=([^\s]+) mode=([^\]]+)\]/(Document Posted on Scribd: http:\/\/www.scribd.com\/doc\/$1 )/gi;
		
		
		return $html;
	}
	
	sub clean_html
	{
		shift if $_[0] eq __PACKAGE__;
		my $html = shift;
		
		# Try to guess if HTML is really just text
		if(!might_be_html($html))
		{
			$html = text2html($html);
		}
		
		# Remove <html> tag, preserve contents
		$html =~ s/<html[^\>]*>((?:.|\n)*)<\/html>/$1/gi;
		# Remove <body> tag, preserve contents
		$html =~ s/<body[^\>]*>((?:.|\n)*)<\/body>/$1/gi;
		# Remove <head> tag and remove contents
		$html =~ s/<head[^\>]*>(.|\n)*<\/head>//gi;
		# Remove <style> tag and remove contents
		$html =~ s/<style[^\>]*>(.|\n)*<\/style>//gi;
		# Remove <title> tag and remove contents
		$html =~ s/<title[^\>]*>(.|\n)*<\/title>//gi;
		# Remove any HTML comments
		$html =~ s/<!--[^\>]*>(.|\n)*-->//gi;
		# Remove DOCTYPE declarations
		$html =~ s/<!DOCTYPE[^\>]*>//gi;
		# Remove <base> tag
		$html =~ s/<base[^\>]*>//gi;
		# Remove <meta> tag
		$html =~ s/<meta[^\>]*>//gi;
		
		# Basic character replacements
		$html =~ s/—/ - /g;
		$html =~ s/–/-/;
		$html =~ s/’/'/g;
		$html =~ s/“/"/g;
		$html =~ s/”/"/g;
		
		# Originates as =A0 in emails, see: http://stackoverflow.com/questions/2774471/what-is-c2-a0-in-mime-encoded-quoted-printable-text
		#my $chr = chr(hex('A0'));
		#$html =~ s/$chr/&nbsp;/g;
		$html =~ s/\x{A0}/&nbsp;/g;
		$html =~ s/\x{C2A0}/&nbsp;/g;
		$html =~ s/\x{00A0}/&nbsp;/g;
		
# 		# Fix qutotation marks - doessnt work
# 		$html =~ s/\x{2019}/'/g;
# 		$html =~ s/\x{0027}/'/g;
		
		# From http://www.codinghorror.com/blog/2006/01/cleaning-words-nasty-html.html
		
		# Get rid of classes and styles
		$html =~ s/\s+style='[^']+'//gi;
		$html =~ s#<(meta|link|/?o:|/?style|/?div|/?st\d|/?head|/?html|body|/?body|/?span|!\[)[^>]*?>"##gi;
		#$html =~ s/(<[^>]+>)+&nbsp;(<\/\w+>)+//gi;
		# remove bizarre v: element attached to <img> tag
		$html =~ s/\s+v:\w+="[^"]+"//gi;
		$html =~ s/(\n\r){2,}"//gi;
		
		# Remove wierd MS HTML
		#$html =~ s/<p(\s+class="MsoNormal")?>(<span([^\>]|\n)+>)?<o:p>.*?&nbsp;<\/o:p>(<\/span>)?<\/p>//g;
		
		return $html;
	}
	
	sub text2html
	{
		shift if $_[0] eq __PACKAGE__;
		my $html = shift;
		my $no_p_wrap = shift;

		# Remove CR
		$html =~ s/\r//g;

		# Simplify blank lines
		$html =~ s/\n\s+\n/\n\n/g;

		if(!$no_p_wrap)
		{
			# If plain text, convert paragraphs to <p>...</p>
			$html =~ s/((?:[^\n]+(?:\n|$))+)/<p>$1<\/p>\n\n/g;
			#$html =~ s/([^\n]+)\n\s*\n/<p>$1<\/p>\n\n/g;
	
			# If the entire thing is only one line, wrap in paragraph tags
			$html = "<p>$html</p>" if $html !~ /\n/;
		}

		# Auto italic/underline/bold based on common conventions in text
		$html =~ s/\*([A-Za-z0-9\!\@\#\$\%\^\&\*\(\)]+)\*/<b>$1<\/b>/g;
		#$html =~ s/\/([A-Za-z0-9\!\@\#\$\%\^\&\*\(\)]+)\//<i>$1<\/i>/g;
		#$html =~ s/_([A-Za-z0-9\!\@\#\$\%\^\&\*\(\)]+)_/<u>$1<\/u>/g;
		$html =~ s/===([^=]+?)===/<h3>$1<\/h3>/g;
		$html =~ s/==([^=]+?)==/<h2>$1<\/h2>/g;
		#$html =~ s/=([^=]+?)=/<h1>$1<\/h1>/g;

		#$html =~ s/{{((?:.|\n)+?)}}/<tt style='white-space:pre-wrap'>$1<\/tt>/g;

		if($html =~ /{{(?:.|\n)+?}}/)
		{
			# Courtesy of http://perlmonks.org/?node_id=1018136
			my @splits = split /({{.*?}})/s, $html;

			my $result="";
			while (my $block = shift @splits)
			{
				$block  =~ s/\n/<br>\n/gs;
				$result .= $block;
				#$result .= shift @splits if @splits;
				if(@splits)
				{
					my $tt = shift @splits;
					$tt =~ s/{{((?:.|\n)+?)}}/<tt style='white-space:pre-wrap'>$1<\/tt>/g;
					#die $tt;
					$result .= $tt;
				}
			}
			#die $result;

			$html = $result;
		}
		else
		{
			# Add <br> between paragraphs with only a single \n linebreak between them
			$html =~ s/([^\n])\n([^\n])/$1<br>\n$2/g;
		}

		$html =~ s/{([^}]+?)}/<tt>$1<\/tt>/g;
		#$html =~ s/\*([^\*]+?)\*/<b>$1<\/b>/g;
		$html =~ s/\s\/([^\/]+?)\/\s/ <i>$1<\/i> /g;
		$html =~ s/\s\_([^\_]+?)\_\s/ <u>$1<\/u> /g;
		$html =~ s/\[([^\|]+?)\|([^\]]+?)\]/<a href='$1'>$2<\/a>/g;
		$html =~ s/\[([^\]]+?)\]/<a href='$1'>$1<\/a>/g;

		# Limit multiple newlines to 2 each
		$html =~ s/\n{2,}/\n\n/sg;
		#$html =~ s/\n/<br>\n/g;

		# Cleanup messy list html
		$html =~ s/<br>\s*\n\s*<br>\s*\n\s*<br>\s*\n/<br>\n/sg;


		
		return $html;
	}
	
	sub might_be_html
	{
		shift if $_[0] eq __PACKAGE__;
		return shift =~ /<[^\>]+>/;
	}
}

package HTML::Template::DelayedLoading;
{
	use strict;
	use base 'HTML::Template';
	
	sub new
	{
		my $class = shift;
		my @args = @_;
		my %hash = @args;
		
		return bless {
			pargs => \%hash,
			params	=> {},
		}, $class;
	}
	
	sub param
	{
		my $self = shift;
		my $key = shift;
		
		if(@_)
		{
			$self->{params}->{$key} = shift;
		}
		
		if(@_)
		{
			warn __PACKAGE__."::param(): This method only handles key=>value arguments - nothing fancy";
		}
		
		return $self->{params}->{$key};
	}
	
	our $CurrentObject;
	sub output
	{
		my $self = shift;
		my %pargs = %{ $self->{pargs} || {} };
		
		$CurrentObject = $self;
		
		$pargs{path} ||= '';
		
		#use Data::Dumper;
		#print STDERR Dumper \%pargs;
		
		my $tmpl = HTML::Template->new(%pargs);
		$tmpl->param(%{ $self->{params} });
		
		#print STDERR __PACKAGE__."::output(): ".Dumper(\%pargs);
		
		my $output = $tmpl->output(@_);
		
		undef $CurrentObject;
		return $output;
	}
	
	
	
};
1;

