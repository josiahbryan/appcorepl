use strict;
package Content::Admin;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';

	my $PAGE_CREATE_ACTION = 'create';
	my $PAGE_EDIT_ACTION = 'edit';
	my $PAGE_DELETE_ACTION = 'delete';
	my $PAGE_SAVE_ACTION = 'save';
	
	__PACKAGE__->WebMethods(qw/ 
		main
		create
		edit
		delete
		save
	/);


	sub new { bless {}, shift }
	
	sub main
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $view = Content::Page::Controller->get_view('admin',$r);
		
		my $tmpl = $self->get_template('list.tmpl');
		my $binpath = $tmpl->param('binpath');
		
		my @pages = Content::Page->retrieve_from_sql('1 order by url');
		
		use Data::Dumper;
		
		my @cols = Content::Page->columns;
		my @list;
		foreach my $page (@pages)
		{
			my $row = {};
			$row->{$_} = $page->get($_) foreach @cols;
			$row->{binpath} = $binpath;
			
			my @url = split /\//, $row->{url};
			shift @url;
			push @url, "<b>". pop(@url). "</b>";
			if(@url == 1)
			{
				$url[0] = "<span class='toplevel'>" . $url[0] . "</span>";
			}
			
			$row->{url_pretty} = '<span class=util>/</span>' . join('<span class=util>/</span>', @url); 
			$row->{in_menus} = $row->{show_in_menus} ? '<b>Yes</b>' : 'No';
			
			#die Dumper $row;
			push @list, $row;
		}
		
		$tmpl->param(pages => \@list);
		#die Dumper \@pages;
		
		$view->output($tmpl);
		return $r;
		
		
	};
	
	sub create
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($PAGE_CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		my $view = Content::Page::Controller->get_view('admin',$r);
		
		my $url = $req->url;
		$url =~ s/^\///;
		
		my $tmpl = $self->get_template('create.tmpl');
		$tmpl->param(page_url => $url);
		
		$tmpl->param(page_title => AppCore::Common::guess_title($url));
		$tmpl->param(page_content => '');
		$tmpl->param(server_name => $AppCore::Config::WEBSITE_SERVER);
		
		$view->output($tmpl);
	
		return $r;
		
	}
	
	sub edit
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($PAGE_CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		my $view = Content::Page::Controller->get_view('admin',$r);
		
		my $url = $req->url;
		
		my $page_obj = Content::Page->by_field(url => $url);
		if(!$page_obj)
		{
			return $r->redirect( $self->module_path($PAGE_CREATE_ACTION) . '?url='. $url);
		}
		
		$url =~ s/^\///;
		
		my $tmpl = $self->get_template('create.tmpl');
		$tmpl->param(page_url => $url);
		$tmpl->param(pageid => $page_obj->id);
		
		$tmpl->param(page_title   => $page_obj->title);
		$tmpl->param(page_content => $page_obj->content);
		$tmpl->param(server_name  => $AppCore::Config::WEBSITE_SERVER);
		
		$view->output($tmpl);
	
		return $r;
	}
	
	sub delete
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $url = $req->url;
		
		my $page_obj = Content::Page->by_field(url => $url);
		if(!$page_obj)
		{
			return $r->error("No such page","No such page: <b>$url</b>");
		}
		
		$page_obj->delete;
		
		return $r->redirect($self->module_url());
	}
	
	sub save
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		#use Data::Dumper;
		#print STDERR Dumper $req;
		
		my $pageid  = $req->pageid;
		my $title   = $req->title;
		my $url     = '/' . $req->url;
		my $content = $req->content;
		
		my $page_obj = $pageid ? Content::Page->retrieve($pageid) : undef;
		
		if(!$page_obj)
		{
			$page_obj = Content::Page->create({url=>$url, typeid=>1});
			print STDERR "Admin: Created pageid $page_obj for url $url\n";
		}
		
		$page_obj->title($title);
		$page_obj->content($content);
		$page_obj->url($url);
		$page_obj->update;
		
		print STDERR "Admin: Updated pageid $pageid - \"$title\"\n";
		
		return $r->redirect($self->module_url());
	}
	
};
1;
