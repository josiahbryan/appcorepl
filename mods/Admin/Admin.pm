use strict;
package Admin;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';
	
	# Use this to access Content::Page::Controller
	use Content::Page;
	
	use Admin::ModuleAdminEntry;
	
	use AppCore::User;
	use AppCore::AuthUtil;
	
	sub new { bless {}, shift }
	
	__PACKAGE__->WebMethods(qw/ 
		main 
		admin_menu
		
	/);
	
	sub apply_mysql_schema
	{
		Admin::ModuleAdminEntry->apply_mysql_schema;
	}
	
	sub main
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		
		#AppCore::Web::Common->redirect("/content/admin");
		
		my $np = $req->next_path;
		if(!$np)
		{
			return $self->admin_menu($req);
		}
		else
		{
			my $r = AppCore::Web::Result->new;
			
			my $entry = Admin::ModuleAdminEntry->by_field(folder_name => $np);
			if(!$entry)
			{
				return $r->error("No Such Admin Entry","Can't find admin entry '$np', sorry!");
			}
			
			$req->push_page_path($req->shift_path);
			
			# Retrieve entry for this admin module and get a blessed ref to the object
			my $pkg = $entry->package;
			my $obj = AppCore::Web::Module->bootstrap($pkg);
			
			# Override AppCore::Web::Module default binpath with our binpath, but modpath stays the same (for file loading, etc)
			$obj->binpath(join('/', $self->binpath, $entry->folder_name));
			
			# Do the actual work...
			my $mod_response = $self->dispatch($req, $pkg);
			
			# If the admin module outputs something other than text/html, let the dispatcher handle the response
			return $mod_response if $mod_response->content_type ne 'text/html';
			
			# Otherwise, we have HTML (should be just a block, not a whole page!!) so we wrap it in our wrapper
			my $tmpl = $self->get_template('wrapper.tmpl');
			$tmpl->param(content_title => $mod_response->content_title);
			$tmpl->param(content_body  => $mod_response->body);
			
			# Send the wrapped HTML out thru the current theme's view for the 'admin' view_code
			my $view = Content::Page::Controller->get_view('admin',$r);
			$view->output($tmpl);
			
			return $r;
		}
	}
	
	sub admin_menu
	{
		my ($self,$req) = shift;
		my $r = AppCore::Web::Result->new;
		
		my $view = Content::Page::Controller->get_view('admin',$r);
		
		my $tmpl = $self->get_template('list.tmpl');
		my @mods = Admin::ModuleAdminEntry->retrieve_from_sql('1 order by title');
		foreach my $mod (@mods)
		{
			$mod->{$_} = $mod->get($_) foreach $mod->columns;
		}
		
		$tmpl->param(list => \@mods);
		
		$view->output($tmpl);
		return $r;
	}
	
# 	sub pages
# 	{
# 		my ($self,$req) = @_;
# 		
# 		AppCore::AuthUtil->require_auth(['ADMIN']);
# 		
# 		return $self->dispatch($req, 'Admin::Pages');
# 	}
	
};

1;
