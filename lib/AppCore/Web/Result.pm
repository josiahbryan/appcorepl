use strict;
# Package: AppCore::Web::Result
# Very simple packaging of a result from a method/webpage/etc. Not a strict HTTP result, but 
# rather something that is more high-level-ish.
# Most basic use:
# $r->output($html)
# Which will store the $html as the body, set status to 200, and content_type to text/html.
# Additionally, it tries to extract the value of the <title> tag from the html as content_title().
# You can also pass an HTML::Template to $r->output and it will do the right thing.
package AppCore::Web::Result;
{
	use vars qw/$AUTOLOAD/;
	
	use AppCore::Common;
	
	# For CSSX functionality and CDN 'mod' url replacement
	use Digest::MD5 qw/md5_hex/;
	
	# Used for CDN 'hash' url replacement
	use Storable;
	
	# Used for CSSX image url() to data: url conversions
	use MIME::Base64;
	
	sub read_file
	{
		my $file = shift;
		open(FILE,"<$file") || die "Cannot open $file for reading: $!";
		my @buffer = <FILE>;
		close(FILE);
		return join '', @buffer;
	}
	
	sub new
	{
		my $class = shift;
		my %args = @_;
		
		$args{status} 		||= 200;
		$args{content_type}	||= 'text/html;charset="utf-8"';
		$args{is_fragment}	||= 1;
	
		bless \%args, $class;
	}
	
	sub x
	{
		my($x,$k,$v)=@_;
		$x->{$k}=$v if defined $v;
		$x->{$k};
	}
	
	sub to_HTTP_Response
	{
		my ($self, $res) = @_;
		
		$res = HTTP::Response->new if !$res;
		$res->add_content($self->body);
		$res->header('Content-Type', $self->content_type);
		$res->code($self->status);
		
		return $res;
	}
	
	sub is_fragment		{shift->x('is_fragment',@_)}
	sub content_title	{shift->x('content_title',@_)}
	sub body		{shift->x('body',@_)}
	sub status		{shift->x('status',@_)}
	sub content_type	{shift->x('content_type',@_)}
	
	sub headers
	{
		my $hdr = shift->{headers} || [];
		return @$hdr;
	}
	
	sub header
	{
		my $self = shift;
		my $name = shift;
		
		$self->{header_map} ||= {};
		return $self->{header_map}->{lc($name)} if $name && !@_;
		
		my $value = shift;
		$self->{header_map}->{lc($name)} = $value;
		
		$self->{headers} ||= [];
		#push @{$self->{headers}}, {name=>$name,value=>$value};
		push @{$self->{headers}}, [$name,$value];
	}
	
	sub has_result
	{
		my $self = shift;
		$self->body || $self->status != 200;
	}
	
	sub redirect
	{
		my $self = shift;
		my $url = shift || '/';
		
		#print "Status: 302\r\nLocation: $url\n\n";
		#exit;
		
		if(AppCore::Common->context->{http_server_brick})
		{
			$self->status(302);
			$self->header('Location',$url);
		
			AppCore::Common->context->{_tmp_result} = $self;
			goto END_HTTP_REQUEST;
		}
		else
		{
			AppCore::Web::Common::redirect($url);
		}
	}
	
	sub error
	{
		my $self = shift;
		my $code = shift;
		my $text = shift;
		
		my $title = $code == 404 ? 'Page Not Found' : 'Website Error';
		
		if($code =~ /[^\d]/)
		{
			$title = $code;
			#$text = "<h1>$title</h1>$text";
			$code = 501;
		}
		
		my $user = AppCore::Common->context->user;
		my $from = undef;
		if($user)
		{
			$from = $user->display . '<'. $user->email.'>';
		}
		
		if(!$user || $user->id !=1)
		{
			my $msg_ref = AppCore::EmailQueue->send_email(
				[AppCore::Config->get('WEBMASTER_EMAIL')],
					"[AppCore Error] Error: $title",
					"Error '$title' in ".AppCore::Web::Common::get_full_url().".\n\n$text",
					1,
					$from);
					
			# Send right away so the user doesn't have to wait for the crontab daemon to run at the top of the minute
			$msg_ref->transmit(2); # timeout
		}
		
		AppCore::Web::Common::error($title,
			($code == 404? ($text? $text : 'The page you requested does not exist or has not been created yet.')
			#." <br><br><b>We are still working hard to finish this website. If you notice any of these missing pages, please email <a href='mailto:webmaster\@productiveconcepts.com'>webmaster\@productiveconcepts.com</a> and let us know. Thanks!</b>" 
			:
			$code == 500? "An error occured:<br><pre>$text</pre>" : "$text").
			"<p>For help with this error, please email <a href='mailto:".AppCore::Config->get('WEBMASTER_EMAIL')
				."?subject=[AppCore] ".AppCore::Web::Common::encode_entities($title)
				."&body=When I went to ".AppCore::Web::Common::encode_entities(AppCore::Web::Common::get_full_url()).", I received this error: "
				.AppCore::Web::Common::encode_entities($text)."'>".AppCore::Config->get('WEBMASTER_EMAIL')."</a>. "
				."Sorry for the trouble!</p><p><a href='javascript:window.history.go(-1)'>&laquo; Return to the previous page ...</a></p>",
		);
	}
	
	sub output
	{
		my $self = shift;
		my $tmpl = shift;
		my $title = shift;
		
		#print STDERR __PACKAGE__."->output($tmpl)\n";
		
		#timemark("start");
		
		my $out = ref $tmpl ? $tmpl->output : $tmpl;
		
		#timemark("output");
		
		#print STDERR "out: $out\n";
		
		if(!$title && index($out,'<title')>-1)
		{
			
			my @titles = $out=~/<title>(.*?)<\/title>/g;
			#$title = $1 if !$title;
			@titles = grep { !/\$/ } @titles;
			$title = shift @titles;
			
			# No head, therefore remove <title> tag
			if(index($out,'<head>') < 0)
			{
				$out=~s/<title>.*?<\/title>//g;
			}
		}
		
# 		if(!$title)
# 		{
# 			my @h1tags = $out=~/<h1>(.*?)<\/h1>/g;
# 			#$title = $1 if !$title;
# 			use Data::Dumper;
# 			die Dumper \@h1tags;
# 			#@h1tags = grep { !/\$/ } @h1tags;
# 			$title = shift @h1tags;
# 		}
		#die Dumper $title;
		
		my $ctype = 'text/html;charset="utf-8"';
		if(index($out,'<content_type')>-1)
		{
			$out=~s/<content_type>(.*?)<\/content_type>//g;
			$ctype = $1 if $1;
		}
		
# 		$self->content_type($ctype);
# 		$self->content_title($title);
# 		$self->body($out);
# 		return $self;
		
		#timemark("preproc");
		
		# Put this inclusion macro up top before other modifications
		# so that any content it includes is processed along with
		# the rest of the content on the pagge
		
		#timemark("tmpl2jq");
		if($out =~ /<(?:\!--)?html/)
		{
			#$out =~ s/©/&copy;/g; # Corrupted entity fixup
			if($out =~ /<a:cssx src=['"][^\"]+['"]/i)
			{	
				#print STDERR "output: found a:cssx tags\n";
				if(AppCore::Config->get('ENABLE_CSSX_COMBINE'))
				{
					#print STDERR "output: a:cssx: combining multuiples\n";
					eval
					{
						my @files = $out =~ /<a:cssx src=["']([^\"']+)["']/gi;
						#$out =~ s/<a:cssx[^\>]+>//gi;
						
						#my $css_link = _process_multi_cssx($self,$tmpl,0,@files);
						#$out =~ s/<\/head>/\t$css_link\n<\/head>/g;
						
						my $file = _process_multi_cssx($self,$tmpl,1,@files);
						my $full_file = AppCore::Config->get('WWW_DOC_ROOT') . $file;
						my $css = read_file($full_file);
						
						if(AppCore::Config->get('ENABLE_INPAGE_CSS_COMBINE'))
						{
							$css .= _combine_inpage_css(\$out);
						}
						
						#$out =~ s/<\/head>/\t<style>$css<\/style>\n<\/head>/g;
						# Instead of inserting at end of head, replace first a:cssx with combined style, then remove all other a:Cssx
						$out =~ s/<a:cssx[^\>]+>/<style>$css<\/style>/i;
						$out =~ s/<a:cssx[^\>]+>//gi;
					};
					warn "Error parsing CSSX files: $@" if $@;
					
				}
				else
				{
					#print STDERR "output: a:cssx: no combine, single processing\n";
					$out =~ s/<a:cssx src="([^\"]+)"[^\>]+>/_process_cssx($self,$tmpl,$1)/segi;
				}
			}
			
			#timemark("cssx combine");
			
			if(AppCore::Config->get('ENABLE_JS_COMBINE') && $out =~ /<script.*?src=['"][^'"]+['"]/i)
			{	
				my @files = $out =~ /<script[^\>]+src=['"]([^'"]+)['"](?:.*?index=['"]([+-]?\d+)['"])?/gi;
				
				my %hash = @files;
				
				use Data::Dumper;
				# Sort scripts by their 'index' attribute
				my @sorted_files = grep { defined $hash{$_} ? $hash{$_} != 0 : 1 } sort { $hash{$a} <=> $hash{$b} } keys %hash;
				my @zeros = grep { defined $hash{$_} && $hash{$_} == 0 } keys %hash;
				
				#die Dumper \%hash;
				
				$out =~ s/<script[^\>]+src=['"]([^'"]+)['"](?:.*?index=['"]([+-]?\d+)['"])?><\/script>//gi;
				
				my $js_link;
				$js_link = _process_multi_js($self,$tmpl,0,@sorted_files) if @sorted_files;
				$js_link = join "\n", $js_link, map { "<script src='$_' index=0></script>" } @zeros;
				my $tmp = "\t$js_link\n</body>";
				$out .= $tmp if ! ($out =~ s/<\/body>/$tmp/gi);
				
			}
			
			#timemark("js combine");
			
			if(AppCore::Config->get('ENABLE_JS_REORDER') && $out =~ /<script(?:\s+type="text\/javascript")?(?:\s+class=["'][^\'"]*["'])?>/)
			{
				#timemark("start js reorder");
				
				my @scripts;
				$out =~ s/<script(?:\s+type="text\/javascript")?(?:\s+class=["'][^\'"]*["'])?>((?:\n|.)+?)<\/script>/push @scripts, $1;''/eg;
				#timemark("jsr - extract1");
				#$out =~ s/<script(?:\s+type="text\/javascript")?(?:\s+class=["'][^\'"]*["'])?>(?:\n|.)+?<\/script>//g;
				#timemark("jsr - extract2");
				my $block = join("\n\n/********************/\n\n", @scripts);
				
				#timemark("jsr - extract3");
				
				if(AppCore::Config->get('ENABLE_JS_REORDER_YUI') &&
				   AppCore::Config->get('USE_YUI_COMPRESS'))
				{
					my $tmp_file = "/tmp/yuic-".md5_hex($block).".js";
					if(-f $tmp_file)
					{
						$block = AppCore::Common->read_file($tmp_file);
					}
					else
					{
						my $comp = AppCore::Config->get('USE_YUI_COMPRESS');
						if($comp =~ /\s([^\s]+\.jar)/ && !-f $1)
						{
							#print STDERR "Unable to find YUI, not compressing. (Looked in $1)\n";
						}
						else
						{
							print STDERR "Compressing in-page scripts to cache $tmp_file with YUI Compress...\n";
							my $tmp_file_pre = "/tmp/yuic.$$.js";
							AppCore::Common->write_file($tmp_file_pre, $block);
							
							my $args = AppCore::Config->get('YUI_COMPRESS_SETTINGS') || '';
							my $cmd = "$comp $tmp_file_pre $args -o $tmp_file";
							print STDERR "YUI Compress command: '$cmd'\n";
							system($cmd);
							
							if( -f $tmp_file )
							{
								$block = AppCore::Common->read_file($tmp_file);
								unlink($tmp_file_pre);
							}
							else
							{
								print STDERR "Error running compressor for URL ".AppCore::Web::Common->get_full_url().": '$tmp_file' never created!\n";
							}
						}
					}
				}
				
				my $tmp = "<script><!--//--><![CDATA[//><!--\n$block//--><!]]></script>\n</body>";
				$out.=$tmp if ! ($out =~ s/<\/body>/$tmp/gi);
				#my $result = $out =~ s/<\/body>/$tmp/gi;
				#print STDERR "ENABLE_JS_REORDER: Result: '$result'\n$out";
				#$out .= $tmp if !$result;
			}
			
			#timemark("js reorder");
			
			if(AppCore::Config->get('ENABLE_CDN_IMG') && _can_cdn_for_fqdn())
			{
				$out =~ s/<img(.*?)src=(['"])(\/[^'"]+)(['"])/"<img$1src=$2".cdn_url($3)."$4"/segi;
			}
			
			#timemark("cdn - img");
			
			if(AppCore::Config->get('ENABLE_CDN_JS') && _can_cdn_for_fqdn())
			{
				$out =~ s/<script src=['"](\/[^'"]+)['"]/"<script src='".cdn_url($1)."'"/segi;
			}
			
			#timemark("cdn - js");
			
			if(AppCore::Config->get('ENABLE_CDN_CSS') && _can_cdn_for_fqdn())
			{
				$out =~ s/<link href=['"](\/[^'"]+)['"]/"<link href='".cdn_url($1)."'"/segi;
			}
			
			#timemark("cdn - css");
			
			if(AppCore::Config->get('ENABLE_CDN_MACRO'))
			{
				if(_can_cdn_for_fqdn())
				{
					#print STDERR "CDN Macro - FQDN\n";
					$out =~ s/\${CDN(?:\:([^\}]+))?}/cdn_url($1)/segi; #egi;
					$out =~ s/\$\(CDN(?:\:([^\)]+))?\)/cdn_url($1)/segi; #egi;
				}
				else
				{
					#print STDERR "CDN Macro - NONFQDN\n";
					$out =~ s/\${CDN(?:\:([^\}]+))?}/$1/gi;
					$out =~ s/\$\(CDN(?:\:([^\)]+))?\)/$1/gi;
				}
			}
			else
			{
				#print STDERR "CDN Macro - Disabled\n";
			}
			
			
			my $ga_id = AppCore::Config->get('GA_ACCOUNT_ID');
			if(AppCore::Config->get('GA_INSERT_TRACKER') && $ga_id)
			{
				
				my $code_to_insert = "";
				my $custom_ga = AppCore::Config->get('GA_CUSTOM_TRACKER');
				if($custom_ga)
				{
					$code_to_insert = $custom_ga;
				}
				else
				{
					my $jq_flag = AppCore::Config->get('GA_USE_JQUERY');
					my $jq_flag = AppCore::Config->get('GA_USE_JQUERY');
					my $jq_head = $jq_flag ? '$(function(){setTimeout(function(){' : '';
					my $jq_footer = $jq_flag ? '}, 50)});' : '';

					# TODO: Upgrade GA code to new code:
					# <script>
					# (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
					# (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
					# m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
					# })(window,document,'script','//www.google-analytics.com/analytics.js','ga');
					# 
					# ga('create', 'UA-243284-29', 'rc.edu');
					# ga('send', 'pageview');
					# 
					# </script>

					my $ga = qq#
			
<script type="text/javascript">
var _gaq = _gaq || [];
_gaq.push(['_setAccount', '$ga_id']);
_gaq.push(['_trackPageview']);
#;
					if(AppCore::Config->get('GA_SET_USER_VAR'))
					{
						my $user = AppCore::Common->context->user;
						my $uid = $user ? $user->display : $ENV{REMOTE_ADDR};
						$ga .= qq{_gaq.push(['_setVar','$uid']);};
					}
					
					$ga .= qq#
$jq_head

(function() {
var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
})();

$jq_footer

</script>
#;
					$code_to_insert = $ga;
				}
				
				
				$out .= $code_to_insert if ! ($out =~ s/<\/body>/$code_to_insert\n<\/body>/gi);
			}
		}
		#
		#timemark("cdn - macro");
		
		$self->content_type($ctype);
		$self->content_title($title);
		$self->body($out);
		
		#timemark("done with output");
		
		#die "Give me a stack trace";
		return $self;
	}
	
	
	sub _combine_inpage_css
	{
		my $out = shift;
		my @css = $$out =~ /<style(?:\s*type="text\/css")?>((?:\n|.)+?)<\/style>/g;
		$$out =~ s/<style(?:\s*type="text\/css")?>(?:\n|.)+?<\/style>//g;
		
		if(AppCore::Config->get('USE_YUI_COMPRESS'))
		{
			my $block = join '', @css;
			my $tmp_file = "/tmp/yuic-".md5_hex($block).".css";
			if(-f $tmp_file)
			{
				$block = AppCore::Common->read_file($tmp_file);
			}
			else
			{
				my $comp = AppCore::Config->get('USE_YUI_COMPRESS');
				if($comp =~ /\s([^\s]+\.jar)/ && !-f $1)
				{
					#print STDERR "Unable to find YUI, not compressing. (Looked in $1)\n";
				}
				else
				{
					print STDERR "Compressing in-page CSS to cache $tmp_file with YUI Compress...\n";
					my $tmp_file_pre = "/tmp/yuic.$$.css";
					AppCore::Common->write_file($tmp_file_pre, $block);
					
					my $args = AppCore::Config->get('YUI_COMPRESS_SETTINGS') || '';
					my $cmd = "$comp $tmp_file_pre $args -o $tmp_file";
					print STDERR "YUI Compress command: '$cmd'\n";
					system($cmd);
					unlink($tmp_file_pre);
					
					$block = AppCore::Common->read_file($tmp_file);
				}
			}
			
			return $block;
		}
		else
		{
			return join '', @css;
		}
	}
	
	sub data_url
	{  
		shift if $_[0] eq __PACKAGE__;
		my $file = shift;
		my $url;
		undef $@;
		eval
		{
			my ($ext) = $file =~ /\.(\w+)$/;
			my $mime = $ext eq 'png' ? 'image/png' :
				   $ext eq 'gif' ? 'image/gif' : 
				   $ext eq 'jpg' ? 'image/jpg' : 'image/unknown';
			
			my $contents = read_file($file);
			my $base64   = encode_base64($contents); 
			$base64 =~ s/\n//g;
			$url = "url('data:$mime;base64,$base64')";
		};
		if($@)
		{
			warn "Error creating data_url for file '$file': $@";
			my $other_url = shift;
			$url = cdn_url($other_url,1)
		}
		return $url;
	}
	
	our $CDNIndex = 0;
	my $CdnDataCache;
	sub cdn_url
	{
		shift if $_[0] eq __PACKAGE__;
		my $url_part = shift;
		my $url_wrap = shift || 0;
		my $NumCdnHosts = scalar @{ AppCore::Config->get('CDN_HOSTS') || [] };
		
		#print STDERR "cdn_url: Input: '$url_part'\n";
		return "url(\"$url_part\")" if !$NumCdnHosts && $url_wrap;
		return $url_part if !$NumCdnHosts;
		
		# Don't add CDN to the URLs that start with the "//" trick
		return $url_part if index($url_part, '//') == 0;
		
		
		my $cdn_mode = AppCore::Config->get('CDN_MODE') || 'hash';
		#print STDERR "cdn_url($url_part): \$cdn_mode: $cdn_mode [AppCore::Config->get('CDN_MODE')]\n";
		if($cdn_mode eq 'rr')
		{
			$CDNIndex ++;
			$CDNIndex = 0 if $CDNIndex >= $NumCdnHosts;
			#print STDERR "cdn_url($url_part): [rr] Round-robin index: $CDNIndex\n";
		}
		elsif($cdn_mode eq 'mod')
		{
			my $hex = md5_hex($url_part);
			
			my $x = 8;
			my $part1 = substr($hex,0,$x);
			my $part2 = substr($hex,$x+=8,8);
			my $part3 = substr($hex,$x+=8,8);
			my $part4 = substr($hex,$x+=8,8);
			
			my $sum = hex($part1); 
			$sum+=hex($part2); 
			$sum+=hex($part3); 
			$sum+=hex($part4);
			
			$CDNIndex = $sum % $NumCdnHosts;
			#print STDERR "cdn_url($url_part): [mod] Modula-derived index: $CDNIndex\n";
		}
		elsif($cdn_mode eq 'hash')
		{
			my $hash_file = AppCore::Config->get('CDN_HASH_FILE');
			my $hash = $CdnDataCache;
			my $mtime = (stat($hash_file))[9];
			if(!$hash || $mtime > $hash->{mtime})
			{
				$hash = $CdnDataCache = -f $hash_file ? Storable::lock_retrieve($hash_file) : {};
				$hash->{mtime} = $mtime;
			}
			my $cache_miss = 0;
			my $idx = defined $hash->{$url_part} ? $hash->{$url_part} : -1;
			if($idx < 0)
			{
				$CDNIndex ++;
				$CDNIndex = 0 if $CDNIndex >= $NumCdnHosts;
				#print STDERR "cdn_url($url_part): [hash] NO CACHED INDEX, USING $CDNIndex\n";
				$cache_miss = 1;
			}
			else
			{
				$CDNIndex = $idx;
				#print STDERR "cdn_url($url_part): [hash] Got cached index: $CDNIndex\n";
			}
			
			$hash->{$url_part} = $CDNIndex;
			#print STDERR "cdn_url($url_part): [hash] Hash file: 'AppCore::Config->get('CDN_HASH_FILE')'\n";
			if($cache_miss || 
				(AppCore::Config->get('CDN_HASH_FORCEWRITE_COUNT') > 0 && 
					(++ $CdnDataCache->{use_count} % AppCore::Config->get('CDN_HASH_FORCEWRITE_COUNT')) == 0
				)
			  )
			{
				Storable::lock_store($hash, $hash_file);
				$hash->{mtime} = (stat($hash_file))[9];
			}
		}

		my $server = AppCore::Config->get('CDN_HOSTS')->[$CDNIndex];
		#print STDERR "cdn_url($url_part): Decided on server $server, #$CDNIndex\n";
		
		my $final_url = join('', '//', $server, $url_part);
		
		#print STDERR "cdn_url: $url_part -> $final_url\n";
		
		return "url(\"$final_url\")" if $url_wrap;
		return $final_url;
	}
	
	sub _can_cdn_for_fqdn
	{
		if(AppCore::Config->get('ENABLE_CDN_FQDN_ONLY'))
		{
			$ENV{HTTP_HOST} = $ENV{HTTP_X_FORWARDED_HOST} if $ENV{HTTP_X_FORWARDED_HOST};
			my $srv = AppCore::Config->get('WEBSITE_SERVER');
			$srv =~ s/^https?:\/\///g;
			my $flag = $ENV{HTTP_HOST} eq $srv ? 1:0;
			#print STDERR "_can_cdn_for_fqdn: srv: $srv, current: $ENV{HTTP_HOST}, flag: $flag\n";
			return $flag; 
		}
		
		return 1;
	}

	sub _read_source_js
	{
		my ($tmpl,$src) = @_;
		my $text = read_file($src);
		$text =~ s/%%([^\%]+)%%/$tmpl->param($1)/segi;
		
		if(AppCore::Config->get('ENABLE_CDN_CSSX_URL') && _can_cdn_for_fqdn())
		{
			$text =~ s/url\(['"](\/[^\"\)]+)["']?\)/'"'.cdn_url($1).'"'/segi;
		}
		
		return $text;
	}
	
	sub _process_multi_js
	{
		my $self = shift;
		my $tmpl = shift;
		my $just_filename = shift || 0;
		
		my @files = @_;
		
		#my $mobile = AppCore::Common->context->x('IsMobile');
		
		my $md5 = md5_hex(join '', @files) . '.js'; # ($mobile ? '-m' : ''). '.css';
		my $jsx_url  = join('/', AppCore::Config->get('WWW_ROOT'), 'cssx', $md5);
		my $jsx_file = AppCore::Config->get('WWW_DOC_ROOT') . $jsx_url;
		
		#my $orig_file = AppCore::Config->get('WWW_DOC_ROOT') . $src_file;
		
		my $need_rebuild = 0;
		if(!-f $jsx_file)
		{
			$need_rebuild = 1;
		}
		else
		{
			my $cache_mod = (stat($jsx_file))[9];
			foreach my $file (@files)
			{
				next if $file =~ /^https?:/;
				my $disk_file = AppCore::Config->get('WWW_DOC_ROOT') . $file;
				if((stat($disk_file))[9] > $cache_mod)
				{
					$need_rebuild = 1;
					last;
				}
			}
		}
		
		if($need_rebuild)
		{
			my @js_buffer;
			foreach my $file (@files)
			{
				next if $file =~ /^https?:/;
				
				my $orig_file = AppCore::Config->get('WWW_DOC_ROOT') . $file;
				print STDERR "Recompiling JS File $orig_file -> $jsx_file\n";
				my $text = _read_source_js($tmpl,$orig_file);
				
				push @js_buffer, $text;
			}
				
			open(CSSX,">$jsx_file") || die "Cannot open $jsx_file for writing: $!";
			print CSSX "/* Built from the following JS files: ".join(', ', @files)." */\n\n";
			print CSSX join "\n", @js_buffer;
			close(CSSX);
			
# 			if(AppCore::Config->get('USE_CSS_TIDY') && 
# 			-f AppCore::Config->get('USE_CSS_TIDY'))
# 			{
# 				my $tmp_file = "/tmp/csstidy.$$.css";
# 				my $args = AppCore::Config->get('CSS_TIDY_SETTINGS') || '-template=highest --discard_invalid_properties=false --compress_colors=true "--remove_last_;=true"';
# 				my $tidy = AppCore::Config->get('USE_CSS_TIDY');
# 				my $cmd = "$tidy $jsx_file $args $tmp_file";
# 				print STDERR "Tidy command: '$cmd'\n";
# 				system($cmd);
# 				system("mv -f $tmp_file $jsx_file");
# 			}
# 			
			if(AppCore::Config->get('USE_YUI_COMPRESS'))
			{
				my $tmp_file = "/tmp/yuic.$$.js";
				my $comp = AppCore::Config->get('USE_YUI_COMPRESS');
				if($comp =~ /\s([^\s]+\.jar)/ && !-f $1)
				{
					#print STDERR "Unable to find YUI, not compressing. (Looked in $1)\n";
				}
				else
				{
					my $args = AppCore::Config->get('YUI_COMPRESS_SETTINGS') || '';
					my $cmd = "$comp $jsx_file $args -o $tmp_file";
					print STDERR "YUI Compress command: '$cmd'\n";
					system($cmd);
					system("mv -f $tmp_file $jsx_file");
				}
			}
		}
		
		return $jsx_url if $just_filename;
		
		if(AppCore::Config->get('ENABLE_CDN_JS') && _can_cdn_for_fqdn())
		{
			$jsx_url = cdn_url($jsx_url);
		}
		
		my @non_local = grep { /^https?:/ } @files;
		my @result = map { "<script src='$_'></script>" } @non_local;
		push @result, "<script src='$jsx_url'></script> <!-- Combined from original JS files: ". join(', ', grep { !/^https?:/ } @files). "-->";
		return join("\n", @result);
	}
	
	

	sub _read_source_css
	{
		my ($tmpl,$src,$mobile) = @_;
		my $text = read_file($src);
		$text =~ s/%%([^\%]+)%%/$tmpl->param($1)/segi;
		
		if(AppCore::Config->get('ENABLE_CSSX_IMAGE_URI') ||
		   ($mobile && AppCore::Config->get('ENABLE_CSSX_MOBILE_IMAGE_URI')))
		{
			my $doc_root = AppCore::Config->get('WWW_DOC_ROOT');
# 			$text =~ s/url\("(\/[^\"]+\.(?:gif|png|jpg))"\);/data_url("AppCore::Config->get('WWW_DOC_ROOT')\/$1") . ";\n\t\t\/* Original Image: $1 *\/"/segi;
			$text =~ s/url\(["']?(\/[^\"\)]+\.(?:gif|png|jpg))["']?\)/data_url("$doc_root\/$1")/segi;
		}
		elsif(AppCore::Config->get('ENABLE_CDN_CSSX_URL') && _can_cdn_for_fqdn())
		{
			#print STDERR "_read_source_css: $src, doing cssx url corrections\n";
			$text =~ s/url\(['"](\/[^\"\)]+\.(?:gif|png|jpg))["']?\)/cdn_url($1,1)/segi;
		}
		else
		{
			#$text =~ s/url\(['"](\/[^\"\)]+\.(?:gif|png|jpg))["']?\)/url("$1")/segi;
		}
		
		return $text;
	}
	
	sub _process_multi_cssx
	{
		my $self = shift;
		my $tmpl = shift;
		my $just_filename = shift || 0;
		
		my @files = @_;
		
		#print STDERR "_process_multi_cssx: files: ".join(', ',@files)."\n";
		
		my $mobile = AppCore::Common->context->x('IsMobile');
		
		my $md5 = md5_hex(join '', @files) . ($mobile ? '-m' : ''). '.css';
		my $cssx_url  = join('/', AppCore::Config->get('WWW_ROOT'), 'cssx', $md5);
		my $cssx_file = AppCore::Config->get('WWW_DOC_ROOT') . $cssx_url;
		
		#my $orig_file = AppCore::Config->get('WWW_DOC_ROOT') . $src_file;
		
		my $need_rebuild = 0;
		if(!-f $cssx_file)
		{
			$need_rebuild = 1;
		}
		else
		{
			my $cache_mod = (stat($cssx_file))[9];
			foreach my $file (@files)
			{
				my $disk_file = AppCore::Config->get('WWW_DOC_ROOT') . $file;
				if((stat($disk_file))[9] > $cache_mod)
				{
					$need_rebuild = 1;
					last;
				}
			}
		}
		
		if($need_rebuild)
		{
			my @css_buffer;
			foreach my $file (@files)
			{
				my $doc_root = AppCore::Config->get('WWW_DOC_ROOT');
				my $orig_file = $doc_root . $file;
				print STDERR "Recompiling CSSX File $orig_file -> $cssx_file\n";
				my $text = _read_source_css($tmpl,$orig_file,$mobile);
				
				# Note: @imports are not processed in included CSS files in order to prevent recursion problems
				if(AppCore::Config->get('ENABLE_CSSX_IMPORT'))
				{
					$text =~ s/\@import url\("([^\"]+)"\);/"\/* Included from: $1 *\/\n"._read_source_css($tmpl,"$doc_root\/$1",$mobile)/segi;
				}
				
				push @css_buffer, $text;
			}
				
			open(CSSX,">$cssx_file") || die "Cannot open $cssx_file for writing: $!";
			print CSSX "/* Built from the following CSS files: ".join(', ', @files)." */\n\n";
			print CSSX join "\n", @css_buffer;
			close(CSSX);
			
			if(AppCore::Config->get('USE_CSS_TIDY') && 
			-f AppCore::Config->get('USE_CSS_TIDY'))
			{
				my $tmp_file = "/tmp/csstidy.$$.css";
				my $args = AppCore::Config->get('CSS_TIDY_SETTINGS') || '-template=highest --discard_invalid_properties=false --compress_colors=true "--remove_last_;=true"';
				my $tidy = AppCore::Config->get('USE_CSS_TIDY');
				my $cmd = "$tidy $cssx_file $args $tmp_file 1>/dev/null 2>&1";
				print STDERR "Tidy command: '$cmd'\n";
				system($cmd);
				system("mv -f $tmp_file $cssx_file");
			}
			
			if(AppCore::Config->get('USE_YUI_COMPRESS'))
			{
				my $tmp_file = "/tmp/csstidy.$$.css";
				my $comp = AppCore::Config->get('USE_YUI_COMPRESS');
				if($comp =~ /\s([^\s]+\.jar)/ && !-f $1)
				{
					print STDERR "Unable to find YUI, not compressing. (Looked in $1)\n";
				}
				else
				{
					my $args = AppCore::Config->get('YUI_COMPRESS_SETTINGS') || '';
					my $cmd = "$comp $cssx_file $args -o $tmp_file";
					print STDERR "YUI Compress command: '$cmd'\n";
					system($cmd);
					system("mv -f $tmp_file $cssx_file");
				}
			}
		}
		
		#print STDERR "_process_multi_cssx: final output file: $cssx_url\n";
		return $cssx_url if $just_filename;
		
		if(AppCore::Config->get('ENABLE_CDN_CSS') && _can_cdn_for_fqdn())
		{
			$cssx_url = cdn_url($cssx_url);
		}
		
		return qq{<link href="$cssx_url" rel="stylesheet" type="text/css" /> <!-- Combined from original CSS files: }. join(', ', @files). '-->';
	}
	
	sub _process_cssx
	{
		my $self = shift;
		my $tmpl = shift;
		my $src_file = shift;
		
		#print STDERR "_process_cssx: tmpl:$tmpl\n";
	
		# Find src
		# Check for compiled ver
		# If found, just replace name
		# Otherwise, compile new ver
		
		my $md5 = md5_hex($src_file).'.css';
		my $doc_root  = AppCore::Config->get('WWW_DOC_ROOT');
		my $cssx_url  = join('/', AppCore::Config->get('WWW_ROOT'), 'cssx', $md5);
		my $cssx_file = $doc_root . $cssx_url;
		my $orig_file = $doc_root . $src_file;
		
		my $mobile = AppCore::Common->context->x('IsMobile');
		
		if(!-f $cssx_file || (stat($cssx_file))[9] < (stat($orig_file))[9])
		{
			print STDERR "Recompiling CSSX File $orig_file -> $cssx_file \n";
			my $text = _read_source_css($tmpl,$orig_file,$mobile);
			
			# Note: @imports are not processed in included CSS files in order to prevent recursion problems
			if(AppCore::Config->get('ENABLE_CSSX_IMPORT'))
			{
				$text =~ s/\@import url\("([^\"]+)"\);/"\/* Included from: $1 *\/\n"._read_source_css($tmpl,"$doc_root\/$1",$mobile)/segi;
			}
			
			open(CSSX,">$cssx_file") || die "Cannot open $cssx_file for writing: $!";
			print CSSX "/* Original CSS File: $src_file */\n\n";
			print CSSX $text;
			close(CSSX);
			
			if(AppCore::Config->get('USE_CSS_TIDY') && 
			-f AppCore::Config->get('USE_CSS_TIDY'))
			{
				my $tmp_file = "/tmp/csstidy.$$.css";
				my $args = AppCore::Config->get('CSS_TIDY_SETTINGS') || '-template=highest --discard_invalid_properties=false --compress_colors=true "--remove_last_;=true"';
				my $tidy = AppCore::Config->get('USE_CSS_TIDY');
				my $cmd = "$tidy $cssx_file $args $tmp_file";
				print STDERR "Tidy command: '$cmd'\n";
				system($cmd);
				system("mv -f $tmp_file $cssx_file");
			}
			
			if(AppCore::Config->get('USE_YUI_COMPRESS'))
			{
				my $tmp_file = "/tmp/csstidy.$$.css";
				my $comp = AppCore::Config->get('USE_YUI_COMPRESS');
				my $args = AppCore::Config->get('YUI_COMPRESS_SETTINGS') || '';
				my $cmd = "$comp $cssx_file $args -o $tmp_file";
				print STDERR "YUI Compress command: '$cmd'\n";
				system($cmd);
				system("mv -f $tmp_file $cssx_file");
			}
		}
		
		if(AppCore::Config->get('ENABLE_CDN_CSS') && _can_cdn_for_fqdn())
		{
			$cssx_url = cdn_url($cssx_url);
		}
		
		#return $cssx_url if $just_filename;
		return qq{<link href="$cssx_url" rel="stylesheet" type="text/css" /> <!-- Original CSS File: $src_file -->};
	}
	
	
	sub output_file
	{
		my $self = shift;
		my $file = shift;
		my $ctype = shift;
# 		$self->content_type($ctype);
# 		$self->body($data);
# 		$self->is_fragment(1);
# 		return $self;

		## XXX HACK here - revisit later
# 		print "Content-Type: $ctype\r\n\r\n";
# 		open(FILE,'<'.$file);
# 		binmode STDOUT;
# 		print $_ while $_ = <FILE>;
# 		close(FILE);
# 		
# 		exit(0);
		$self->content_type($ctype);
		$self->body(read_file($file));
		$self->is_fragment(0);
		
		return $self;
	}
	
	sub output_data
	{
		my $self = shift;
		my $ctype = shift;
		my $data = join '', @_;
		$self->content_type($ctype);
		$self->body($data);
		$self->is_fragment(1);
		return $self;
	}


	sub AUTOLOAD 
	{
		my $node = shift;
		my $name = $AUTOLOAD;
		$name =~ s/.*:://;   # strip fully-qualified portion
		
		return if $name eq 'DESTROY';
		
		#AppCore::Common::print_stack_trace();
		#print STDERR "DEBUG: AUTOLOAD() [$node] ACCESS $name\n"; # if $debug;
		return if !$node || !ref $node;		
		return $node->x($name,@_);
	}
	
# 	sub convert_to_eas_response
# 	{
# 		my $r = shift;
# 		my $default_title = shift;
# 		
# 		my $out;
# 		if(!$r->is_fragment || $r->content_type ne 'text/html') # || index($r->body,'<head>')>-1)
# 		{
# 			$out = $r->body;
# 		}
# 		else
# 		{
# 			$out = AppCore::Web::Common::master_template($r->content_title || $default_title || 'EAS', $r->body);
# 			if($r->header('X-Disable-EASMAsterNav'))
# 			{
# 				#$out->param(disable_nav => 1);
# 			}
# 			$out = $out->output;
# 		}
# 		
# # 		print STDERR "Status:\t ".$r->status."\n".
# # 			"Content-Type:\t ".$r->content_type."\n".
# # 			"\n".
# # 			"$out\n".
# # 			"------------\n";
# 		
# 		return AppCore::Web::Common::HTTP($r->status, $r->content_type, $out);
# 	}

}

1;
