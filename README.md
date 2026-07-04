# xml2rdf_koha

![Perl](https://img.shields.io/badge/perl-5.42.2-blue.svg) ![Version](https://img.shields.io/badge/version_0.1)


This is a small university project @ TH Wildau.

Idea: Parse our MarcXML data to RDF (Turtle) and save the triplets in a apache jena fuseki database. Then visualize the data as a knowledge graph.

STATUS:
- [X] Get MarcXML Data
- [X] Set up apache Jena Fuseki as docker container
- [ ] Define a Data Model
- [ ] Write first script for the parser
- [ ] Write first script for the database integration
- [ ] Write first script for the visualization

Future:
- [ ] Seperate the xml2rdf package from the project (Because this is a small project by its own)

My goal: At the end I want this to be a koha plugin, for easy convertig MarcXML to Turtle format and having a nive integration for the OPAC, so that the users can browser our data by graph, instead of a list.

Feel free to commit :)
