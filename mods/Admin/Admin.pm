use strict;
package Admin;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';
	
	# Use this to access Content::Page::Controller
	use Content::Page;
	
	use AppCore::User;
	use AppCore::AuthUtil;
	
	sub new { bless {}, shift }
	
	my $PAGE_ROOT = 'pages';
	
	__PACKAGE__->WebMethods(qw/ 
		main 
		pages
	/);
	
	sub main
	{
		my ($self,$req) = shift;
		
		AppCore::Web::Common->redirect($self->module_url($PAGE_ROOT));
	}
	
	sub pages
	{
		my ($self,$req) = @_;
		
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		return $self->dispatch($req, 'Admin::Pages');
	}
	
};

package Admin::Pages;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';

	my $PAGE_CREATE_ACTION = 'create';
	my $PAGE_EDIT_ACTION = 'edit';
	my $PAGE_DELETE_ACTION = 'delete';
	my $PAGE_SAVE_ACTION = 'save';
	
	__PACKAGE__->WebMethods(qw/ 
		create
		edit
		delete
		save
	/);


	sub new { bless {}, shift }
	
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
		
		return $r->redirect('/admin');
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
		
		return $r->redirect($url);
	}
	
};
1;
