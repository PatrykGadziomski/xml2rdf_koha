package Marc2RDF::Triple;
use strict;
use warnings;

package Marc2RDF::Triple;
use strict;
use warnings;

sub new {
    my ($class, $subject, $predicate, $object, %opts) = @_;
    return bless {
        subject   => $subject,
        predicate => $predicate,
        object    => $object,
        is_literal => $opts{is_literal} // 1,   # 1 = Objekt ist Literal, 0 = IRI
        lang       => $opts{lang},               # optionales Sprachtag
        datatype   => $opts{datatype},           # optionaler xsd:-Typ
    }, $class;
}

sub subject   { $_[0]->{subject} }
sub predicate { $_[0]->{predicate} }
sub object    { $_[0]->{object} }
sub is_literal { $_[0]->{is_literal} }
sub lang      { $_[0]->{lang} }
sub datatype  { $_[0]->{datatype} }

1;