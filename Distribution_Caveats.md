### Distribution Caveats ###
  * I had to rip out the MGC proprietary code.  Nothing big.  Stuff like server names, network paths, etc.  You would have had to change it yourself anyway.  Start with `src/cqsvrvars.pm`, read the admin docs and look over the code for obvious hard-coded values.
  * The admin doc 'Logging-in to the CQ/XML Server' was intentionally removed from the public distribution.