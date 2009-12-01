require 'rubygems'; require 'hpricot'; require 'open-uri'
F = File.open("Glyphs.lua", 'w'); F.write "GlyphTrader.GLYPHS = {\n"
g = []; [6,11,3,8,2,5,4,7,9,1].each do |k| ["MAJOR", "MINOR"].each do |t|
g << (Hpricot(open("http://www.wowarmory.com/search.xml?searchQuery=\
&fl[source]=all&fl[type]=glyphs&fl[usbleBy]=%d&fl[glyphTp]=%s&searchType=\
items"%[k,t])) / "#searchResultsTable tbody a.itemToolTip").map do |e|
  name = e.inner_html.gsub("Glyph of ","").gsub(/^[a-z]/){|l|l.upcase}
  "  [%s] = \"%s\"" % [e.attributes["id"], name]; end; end; end
F.write g.join(",\n") + "\n}\n"; F.close