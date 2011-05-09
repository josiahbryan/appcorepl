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
		$args{content_type}	||= 'text/html';
		$args{is_fragment}	||= 1;
	
		bless \%args, $class;
	}
	
	sub x
	{
		my($x,$k,$v)=@_;
		$x->{$k}=$v if defined $v;
		$x->{$k};
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
		push @{$self->{headers}}, {name=>$name,value=>$value};
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
		#$self->status(302);
		#$self->header('Location',$url);
		#print "Status: 302\r\nLocation: $url\n\n";
		#exit;
		AppCore::Web::Common::redirect($url);
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
			#AppCore::Web::Common::send_email([$AppCore::Config::WEBMASTER_EMAIL],"[AppCore Error] Error: $title","Error '$title' in ".AppCore::Web::Common::get_full_url().".\n\n$text",1,$from);
		}
		
		AppCore::Web::Common::error($title,
			($code == 404? ($text? $text : 'The page you requested does not exist or has not been created yet.')
			#." <br><br><b>We are still working hard to finish this website. If you notice any of these missing pages, please email <a href='mailto:webmaster\@productiveconcepts.com'>webmaster\@productiveconcepts.com</a> and let us know. Thanks!</b>" 
			:
			$code == 500? "An error occured:<br><pre>$text</pre>" : "$text").
			"<p>For help with this error, please email <a href='mailto:$AppCore::Config::WEBMASTER_EMAIL"
				."?subject=[AppCore] ".AppCore::Web::Common::encode_entities($title)
				."&body=When I went to ".AppCore::Web::Common::encode_entities(AppCore::Web::Common::get_full_url()).", I received this error: "
				.AppCore::Web::Common::encode_entities($text)."'>$AppCore::Config::WEBMASTER_EMAIL</a>. "
				."Sorry for the trouble!</p><p><a href='javascript:window.history.go(-1)'>&laquo; Return to the previous page ...</a></p>",
		);
	}
	
	sub output
	{
		my $self = shift;
		my $tmpl = shift;
		my $title = shift;
		
		#print STDERR __PACKAGE__."->output($tmpl)\n";
		
		my $out = ref $tmpl ? $tmpl->output : $tmpl;
		
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
		
		my $ctype = 'text/html';
		if(index($out,'<content_type')>-1)
		{
			$out=~s/<content_type>(.*?)<\/content_type>//g;
			$ctype = $1 if $1;
		}
		
		# Put this inclusion macro up top before other modifications
		# so that any content it includes is processed along with
		# the rest of the content on the pagge
		if($AppCore::Config::ENABLE_TMPL2JQ_MACRO)
		{
			$out =~ s/\${TMPL2JQ:([^\}]+)}/_tmpl2jq($1,$tmpl)/segi;
		}
		
		if($out =~ /<a:cssx src=['"][^\"]+['"]/i)
		{	
			if($AppCore::Config::ENABLE_CSSX_COMBINE)
			{
				my @files = $out =~ /<a:cssx src="([^\"]+)"/gi;
				$out =~ s/<a:cssx[^\>]+>//gi;
				#my $css_link = _process_multi_cssx($self,$tmpl,0,@files);
				#$out =~ s/<\/head>/\t$css_link\n<\/head>/g;
				
				my $file = _process_multi_cssx($self,$tmpl,1,@files);
				my $full_file = $AppCore::Config::WWW_DOC_ROOT . $file;
				my $css = read_file($full_file);
				
				if($AppCore::Config::ENABLE_INPAGE_CSS_COMBINE)
				{
					$css .= _combine_inpage_css(\$out);
				}
				
				$out =~ s/<\/head>/\t<style>$css<\/style>\n<\/head>/g;
				
			}
			else
			{
				$out =~ s/<a:cssx src="([^\"]+)"[^\>]+>/_process_cssx($self,$tmpl,$1)/segi;
			}
		}
		
		if($AppCore::Config::ENABLE_JS_COMBINE && $out =~ /<script.*?src=['"][^'"]+['"]/i)
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
		
		if($AppCore::Config::ENABLE_JS_REORDER && $out =~ /<script(?:\s+type="text\/javascript")?>/)
		{
			my @scripts = $out =~ /<script(?:\s+type="text\/javascript")?>((?:\n|.)+?)<\/script>/g;
			$out =~ s/<script(?:\s+type="text\/javascript")?>(?:\n|.)+?<\/script>//g;
			my $block = join("\n\n/********************/\n\n", @scripts);
			
			if($AppCore::Config::ENABLE_JS_REORDER_YUI &&
			   $AppCore::Config::USE_YUI_COMPRESS)
			{
				my $tmp_file = "/tmp/yuic-".md5_hex($block).".js";
				if(-f $tmp_file)
				{
					$block = AppCore::Common->read_file($tmp_file);
				}
				else
				{
					my $comp = $AppCore::Config::USE_YUI_COMPRESS;
					if($comp =~ /\s([^\s]+\.jar)/ && !-f $1)
					{
						print STDERR "Unable to find YUI, not compressing. (Looked in $1)\n";
					}
					else
					{
						print STDERR "Compressing in-page scripts to cache $tmp_file with YUI Compress...\n";
						my $tmp_file_pre = "/tmp/yuic.$$.js";
						AppCore::Common->write_file($tmp_file_pre, $block);
						
						my $args = $AppCore::Config::YUI_COMPRESS_SETTINGS || '';
						my $cmd = "$comp $tmp_file_pre $args -o $tmp_file";
						print STDERR "YUI Compress command: '$cmd'\n";
						system($cmd);
						unlink($tmp_file_pre);
						
						if( -f $tmp_file )
						{
							$block = AppCore::Common->read_file($tmp_file);
						}
						else
						{
							print STDERR "Error running compressor - '$tmp_file' never created!\n";
						}
					}
				}
			}
			
			my $tmp = "<script>$block</script>\n</body>";
			$out.=$tmp if ! ($out =~ s/<\/body>/$tmp/gi);
		}
		
		if($AppCore::Config::ENABLE_CDN_IMG && _can_cdn_for_fqdn())
		{
			$out =~ s/<img src=['"](\/[^'"]+)['"]/"<img src='".cdn_url($1)."'"/segi;
		}
		
		if($AppCore::Config::ENABLE_CDN_JS && _can_cdn_for_fqdn())
		{
			$out =~ s/<script src=['"](\/[^'"]+)['"]/"<script src='".cdn_url($1)."'"/segi;
		}
		
		if($AppCore::Config::ENABLE_CDN_CSS && _can_cdn_for_fqdn())
		{
			$out =~ s/<link href=['"](\/[^'"]+)['"]/"<link href='".cdn_url($1)."'"/segi;
		}
		
		if($AppCore::Config::ENABLE_CDN_MACRO)
		{
			if(_can_cdn_for_fqdn())
			{
				$out =~ s/\${CDN(?:\:([^\}]+))?}/cdn_url($1)/segi;
				$out =~ s/\$\(CDN(?:\:([^\)]+))?\)/cdn_url($1)/segi;
			}
			else
			{
				$out =~ s/\${CDN(?:\:([^\}]+))?}/$1/segi;
				$out =~ s/\$\(CDN(?:\:([^\)]+))?\)/$1/segi;
			}
		}
		
		$self->content_type($ctype);
		$self->content_title($title);
		$self->body($out);
		return $self;
	}
	
	sub _tmpl2jq
	{
		my $file = shift;
		my $tmpl = shift;
		my $block = AppCore::Web::Common->get_included_file($file);
		#$block =~ s/<tmpl_if ([^>]+?)>/{{if $1}}/segi;
		$block =~ s/<tmpl_if ([^>]+?)>/_tmpl_if2jq($1,$block)/segi;
		$block =~ s/<\/tmpl_if>/{{\/if}}/gi;
		$block =~ s/<tmpl_loop ([^>]+?)>/{{each $1}}/gi;
		$block =~ s/<\/tmpl_loop>/{{\/each}}/gi;
		$block =~ s/<tmpl_else>/{{else}}/gi;
		$block =~ s/<tmpl_var ([^>]+)>/$tmpl->param($1)/segi if $tmpl;
		$block =~ s/%%(.+?html)%%/{{html $1}}/g;
		$block =~ s/%%([^\%]+)%%/\${$1}/g;

		#print STDERR "Final block: $block\n";
		
		return $block;
	}
	
	sub _tmpl_if2jq
	{
		my $var = shift;
		my $block = shift;
		if($block =~ /<tmpl_loop $var>/)
		{
			return "{{if $var.length}}";
		}
		else
		{
			return "{{if $var}}";
		}
	}
	
	sub _combine_inpage_css
	{
		my $out = shift;
		my @css = $$out =~ /<style(?:\s*type="text\/css")?>((?:\n|.)+?)<\/style>/g;
		$$out =~ s/<style(?:\s*type="text\/css")?>(?:\n|.)+?<\/style>//g;
		
		if($AppCore::Config::USE_YUI_COMPRESS)
		{
			my $block = join '', @css;
			my $tmp_file = "/tmp/yuic-".md5_hex($block).".css";
			if(-f $tmp_file)
			{
				$block = AppCore::Common->read_file($tmp_file);
			}
			else
			{
				my $comp = $AppCore::Config::USE_YUI_COMPRESS;
				if($comp =~ /\s([^\s]+\.jar)/ && !-f $1)
				{
					print STDERR "Unable to find YUI, not compressing. (Looked in $1)\n";
				}
				else
				{
					print STDERR "Compressing in-page CSS to cache $tmp_file with YUI Compress...\n";
					my $tmp_file_pre = "/tmp/yuic.$$.css";
					AppCore::Common->write_file($tmp_file_pre, $block);
					
					my $args = $AppCore::Config::YUI_COMPRESS_SETTINGS || '';
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
		my ($ext) = $file =~ /\.(\w+)$/;
		my $mime = $ext eq 'png' ? 'image/png' :
		           $ext eq 'gif' ? 'image/gif' : 
		           $ext eq 'jpg' ? 'image/jpg' : 'image/unknown';
		
		my $contents = read_file($file);
		my $base64   = encode_base64($contents); 
		$base64 =~ s/\n//g;
		return "url('data:$mime;base64,$base64')";
	}
	
	our $CDNIndex = @AppCore::Config::CDN_HOSTS;
	sub cdn_url
	{
		shift if $_[0] eq __PACKAGE__;
		my $url_part = shift;
		my $url_wrap = shift || 0;
		#return "url(\"$url_part\")" if !@AppCore::Config::CDN_HOSTS && $url_wrap;
		return $url_part if !@AppCore::Config::CDN_HOSTS;
		
		my $cdn_mode = $AppCore::Config::CDN_MODE || 'hash';
		#print STDERR "cdn_url($url_part): \$cdn_mode: $cdn_mode [$AppCore::Config::CDN_MODE]\n";
		if($cdn_mode eq 'rr')
		{
			$CDNIndex ++;
			$CDNIndex = 0 if $CDNIndex >= @AppCore::Config::CDN_HOSTS;
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
			
			$CDNIndex = $sum % scalar(@AppCore::Config::CDN_HOSTS);
			#print STDERR "cdn_url($url_part): [mod] Modula-derived index: $CDNIndex\n";
		}
		elsif($cdn_mode eq 'hash')
		{
			#Storable
			my $hash = -f $AppCore::Config::CDN_HASH_FILE ? Storable::lock_retrieve($AppCore::Config::CDN_HASH_FILE) : {};
			my $idx = defined $hash->{$url_part} ? $hash->{$url_part} : -1;
			if($idx < 0)
			{
				$CDNIndex ++;
				$CDNIndex = 0 if $CDNIndex >= @AppCore::Config::CDN_HOSTS;
				#print STDERR "cdn_url($url_part): [hash] NO CACHED INDEX, USING $CDNIndex\n";
			}
			else
			{
				$CDNIndex = $idx;
				#print STDERR "cdn_url($url_part): [hash] Got cached index: $CDNIndex\n";
			}
			
			$hash->{$url_part} = $CDNIndex;
			#print STDERR "cdn_url($url_part): [hash] Hash file: '$AppCore::Config::CDN_HASH_FILE'\n";
			Storable::lock_store($hash, $AppCore::Config::CDN_HASH_FILE);
		}

		my $server = $AppCore::Config::CDN_HOSTS[$CDNIndex];
		#print STDERR "cdn_url($url_part): Decided on server $server, #$CDNIndex\n";
		
		my $final_url = join('', 'http://', $server, $url_part);
		
		return "url(\"$final_url\")" if $url_wrap;
		return $final_url;
	}
	
	sub _can_cdn_for_fqdn
	{
		if($AppCore::Config::ENABLE_CDN_FQDN_ONLY)
		{
			$ENV{HTTP_HOST} = $ENV{HTTP_X_FORWARDED_HOST} if $ENV{HTTP_X_FORWARDED_HOST};
			my $srv = $AppCore::Config::WEBSITE_SERVER;
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
		
		if($AppCore::Config::ENABLE_CDN_CSSX_URL && _can_cdn_for_fqdn())
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
		my $jsx_url  = join('/', $AppCore::Config::WWW_ROOT, 'cssx', $md5);
		my $jsx_file = $AppCore::Config::WWW_DOC_ROOT . $jsx_url;
		
		#my $orig_file = $AppCore::Config::WWW_DOC_ROOT . $src_file;
		
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
				my $disk_file = $AppCore::Config::WWW_DOC_ROOT . $file;
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
				
				my $orig_file = $AppCore::Config::WWW_DOC_ROOT . $file;
				print STDERR "Recompiling JS File $orig_file -> $jsx_file\n";
				my $text = _read_source_js($tmpl,$orig_file);
				
				push @js_buffer, $text;
			}
				
			open(CSSX,">$jsx_file") || die "Cannot open $jsx_file for writing: $!";
			print CSSX "/* Built from the following JS files: ".join(', ', @files)." */\n\n";
			print CSSX join "\n", @js_buffer;
			close(CSSX);
			
# 			if($AppCore::Config::USE_CSS_TIDY && 
# 			-f $AppCore::Config::USE_CSS_TIDY)
# 			{
# 				my $tmp_file = "/tmp/csstidy.$$.css";
# 				my $args = $AppCore::Config::CSS_TIDY_SETTINGS || '-template=highest --discard_invalid_properties=false --compress_colors=true "--remove_last_;=true"';
# 				my $tidy = $AppCore::Config::USE_CSS_TIDY;
# 				my $cmd = "$tidy $jsx_file $args $tmp_file";
# 				print STDERR "Tidy command: '$cmd'\n";
# 				system($cmd);
# 				system("mv -f $tmp_file $jsx_file");
# 			}
# 			
			if($AppCore::Config::USE_YUI_COMPRESS)
			{
				my $tmp_file = "/tmp/yuic.$$.js";
				my $comp = $AppCore::Config::USE_YUI_COMPRESS;
				if($comp =~ /\s([^\s]+\.jar)/ && !-f $1)
				{
					print STDERR "Unable to find YUI, not compressing. (Looked in $1)\n";
				}
				else
				{
					my $args = $AppCore::Config::YUI_COMPRESS_SETTINGS || '';
					my $cmd = "$comp $jsx_file $args -o $tmp_file";
					print STDERR "YUI Compress command: '$cmd'\n";
					system($cmd);
					system("mv -f $tmp_file $jsx_file");
				}
			}
		}
		
		return $jsx_url if $just_filename;
		
		if($AppCore::Config::ENABLE_CDN_JS && _can_cdn_for_fqdn())
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
		
		if($AppCore::Config::ENABLE_CSSX_IMAGE_URI ||
		   ($mobile && $AppCore::Config::ENABLE_CSSX_MOBILE_IMAGE_URI))
		{
# 			$text =~ s/url\("(\/[^\"]+\.(?:gif|png|jpg))"\);/data_url("$AppCore::Config::WWW_DOC_ROOT\/$1") . ";\n\t\t\/* Original Image: $1 *\/"/segi;
			$text =~ s/url\(["']?(\/[^\"\)]+\.(?:gif|png|jpg))["']?\)/data_url("$AppCore::Config::WWW_DOC_ROOT\/$1")/segi;
		}
		elsif($AppCore::Config::ENABLE_CDN_CSSX_URL && _can_cdn_for_fqdn())
		{
			$text =~ s/url\(['"](\/[^\"\)]+\.(?:gif|png|jpg))["']?\)/cdn_url($1,1)/segi;
		}
		
		return $text;
	}
	
	sub _process_multi_cssx
	{
		my $self = shift;
		my $tmpl = shift;
		my $just_filename = shift || 0;
		
		my @files = @_;
		
		my $mobile = AppCore::Common->context->x('IsMobile');
		
		my $md5 = md5_hex(join '', @files) . ($mobile ? '-m' : ''). '.css';
		my $cssx_url  = join('/', $AppCore::Config::WWW_ROOT, 'cssx', $md5);
		my $cssx_file = $AppCore::Config::WWW_DOC_ROOT . $cssx_url;
		
		#my $orig_file = $AppCore::Config::WWW_DOC_ROOT . $src_file;
		
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
				my $disk_file = $AppCore::Config::WWW_DOC_ROOT . $file;
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
				my $orig_file = $AppCore::Config::WWW_DOC_ROOT . $file;
				print STDERR "Recompiling CSSX File $orig_file -> $cssx_file\n";
				my $text = _read_source_css($tmpl,$orig_file,$mobile);
				
				# Note: @imports are not processed in included CSS files in order to prevent recursion problems
				if($AppCore::Config::ENABLE_CSSX_IMPORT)
				{
					$text =~ s/\@import url\("([^\"]+)"\);/"\/* Included from: $1 *\/\n"._read_source_css($tmpl,"$AppCore::Config::WWW_DOC_ROOT\/$1",$mobile)/segi;
				}
				
				push @css_buffer, $text;
			}
				
			open(CSSX,">$cssx_file") || die "Cannot open $cssx_file for writing: $!";
			print CSSX "/* Built from the following CSS files: ".join(', ', @files)." */\n\n";
			print CSSX join "\n", @css_buffer;
			close(CSSX);
			
			if($AppCore::Config::USE_CSS_TIDY && 
			-f $AppCore::Config::USE_CSS_TIDY)
			{
				my $tmp_file = "/tmp/csstidy.$$.css";
				my $args = $AppCore::Config::CSS_TIDY_SETTINGS || '-template=highest --discard_invalid_properties=false --compress_colors=true "--remove_last_;=true"';
				my $tidy = $AppCore::Config::USE_CSS_TIDY;
				my $cmd = "$tidy $cssx_file $args $tmp_file";
				print STDERR "Tidy command: '$cmd'\n";
				system($cmd);
				system("mv -f $tmp_file $cssx_file");
			}
			
			if($AppCore::Config::USE_YUI_COMPRESS)
			{
				my $tmp_file = "/tmp/csstidy.$$.css";
				my $comp = $AppCore::Config::USE_YUI_COMPRESS;
				if($comp =~ /\s([^\s]+\.jar)/ && !-f $1)
				{
					print STDERR "Unable to find YUI, not compressing. (Looked in $1)\n";
				}
				else
				{
					my $args = $AppCore::Config::YUI_COMPRESS_SETTINGS || '';
					my $cmd = "$comp $cssx_file $args -o $tmp_file";
					print STDERR "YUI Compress command: '$cmd'\n";
					system($cmd);
					system("mv -f $tmp_file $cssx_file");
				}
			}
		}
		
		return $cssx_url if $just_filename;
		
		if($AppCore::Config::ENABLE_CDN_CSS && _can_cdn_for_fqdn())
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
		my $cssx_url  = join('/', $AppCore::Config::WWW_ROOT, 'cssx', $md5);
		my $cssx_file = $AppCore::Config::WWW_DOC_ROOT . $cssx_url;
		my $orig_file = $AppCore::Config::WWW_DOC_ROOT . $src_file;
		
		my $mobile = AppCore::Common->context->x('IsMobile');
		
		if(!-f $cssx_file || (stat($cssx_file))[9] < (stat($orig_file))[9])
		{
			print STDERR "Recompiling CSSX File $orig_file -> $cssx_file \n";
			my $text = _read_source_css($tmpl,$orig_file,$mobile);
			
			# Note: @imports are not processed in included CSS files in order to prevent recursion problems
			if($AppCore::Config::ENABLE_CSSX_IMPORT)
			{
				$text =~ s/\@import url\("([^\"]+)"\);/"\/* Included from: $1 *\/\n"._read_source_css($tmpl,"$AppCore::Config::WWW_DOC_ROOT\/$1",$mobile)/segi;
			}
			
			open(CSSX,">$cssx_file") || die "Cannot open $cssx_file for writing: $!";
			print CSSX "/* Original CSS File: $src_file */\n\n";
			print CSSX $text;
			close(CSSX);
			
			if($AppCore::Config::USE_CSS_TIDY && 
			-f $AppCore::Config::USE_CSS_TIDY)
			{
				my $tmp_file = "/tmp/csstidy.$$.css";
				my $args = $AppCore::Config::CSS_TIDY_SETTINGS || '-template=highest --discard_invalid_properties=false --compress_colors=true "--remove_last_;=true"';
				my $tidy = $AppCore::Config::USE_CSS_TIDY;
				my $cmd = "$tidy $cssx_file $args $tmp_file";
				print STDERR "Tidy command: '$cmd'\n";
				system($cmd);
				system("mv -f $tmp_file $cssx_file");
			}
			
			if($AppCore::Config::USE_YUI_COMPRESS)
			{
				my $tmp_file = "/tmp/csstidy.$$.css";
				my $comp = $AppCore::Config::USE_YUI_COMPRESS;
				my $args = $AppCore::Config::YUI_COMPRESS_SETTINGS || '';
				my $cmd = "$comp $cssx_file $args -o $tmp_file";
				print STDERR "YUI Compress command: '$cmd'\n";
				system($cmd);
				system("mv -f $tmp_file $cssx_file");
			}
		}
		
		if($AppCore::Config::ENABLE_CDN_CSS && _can_cdn_for_fqdn())
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
		print "Content-Type: $ctype\r\n\r\n";
		open(FILE,'<'.$file);
		binmode STDOUT;
		print $_ while $_ = <FILE>;
		close(FILE);
		
		exit(0);
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
