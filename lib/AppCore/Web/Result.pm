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
		
		
		$self->content_type($ctype);
		$self->content_title($title);
		$self->body($out);
		return $self;
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
