def nonempty: type == "string" and length > 0;
def entry:
  type == "object" and
  (.owner | nonempty) and (.repo | nonempty) and
  (.version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.hash | type == "string" and test("^sha256-[A-Za-z0-9+/]{43}=$"));
type == "object" and
(keys == ["codexbar-cli", "codexbar-plasma"]) and
(."codexbar-cli" | entry) and
(."codexbar-plasma" | entry) and
(."codexbar-cli" | .asset == ("CodexBarCLI-v" + .version + "-linux-x86_64.tar.gz"))
