AppCore provides a suite of perl classes for modules and common web routines, DBI wrapper classes, CGI dispatchers, and example Apache configs for creating dynamic websites and web applications with minimal coding.

  * DBI Wrapper (AppCore::DBI) extends Class::DBI to provide a simple yet robust meta-data  system for reflection and auto-table schema updating
  * CGI Dispatchers
    * FastCGI dispatcher (index.fcgi)
    * Plain CGI dispatcher (index.cgi)
  * Example Apache Configs provide mod\_rewrite rules for seamlessly run appcore using clean path names. For example:
    * Instead of: /index.fcgi/help/aboutus
    * mod\_rewrite allows: /help/aboutus
    * All without having to pre-specify your root URLs (such as /help, /products, etc.)
    * mod\_rewrite configs show how to serve existing files thru apache and send unknown URLs thru to your dispatcher
  * Modules/Classes:
    * AppCore::User and AppCore::AuthUtil are integrated into the dispatchers for automatic authentication of each request. Note that the dispatchers don't reject unauthenticated requests automatically - that's up to the actual code that runs to decide what to do with such requests.
    * AppCore::Common and AppCore::Web::Common provide common routines for date parsing, time handling, escaping/unescaping, entity handling, etc
    * AppCore::Request and AppCore::Result wrap request parameters and handle outputing data via the appropriate method for the current dispatcher, provide access to cookies, etc
    * AppCore::Web::Module provides a common baseclass for user's modules

AppCore expects you to write your code as 'modules' under /appcore/modules. Included modules currently are:
  * Content - Provides a simple CMS-like setup. Content is the default module for unknown URLs that arrive at the dispatcher (e.g. not handled by another module).
    * Content implements a themeing engine (Content::Page::ThemeEngine) with the current theme configureable in AppCore::Config. Themes are implemented as modules, with the included theme being ThemeBasic (others to come.)
    * Content provides pages (Content::Page) stored in the database
    * Content also provides page types (think a MVC paradigm - Content::Page::Type index the available controllers for a page, with the built-in controller being Content::Page::Controller which just implements a static page.)
    * Other modules can implement their own custom Content::Page::Controller classes and register them by creating a Content::Page::Type instance in the database
  * Login
    * A simple login screen that honors the current theme used in the Content module
    * We plan to add Facebook login integration soon


