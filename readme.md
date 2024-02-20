# CONCOM
Conventional commit tool (read about them
[here](https://www.conventionalcommits.org/en/v1.0.0/)).

## Usage

### Validate
```bash
# validate a git reference (a commitish)
concom validate --ref HEAD

# validate a msg provided on stdin
git show -s --format=%B HEAD | concom validate

# validate a msg from file ... useful for e.g. .git/hooks/pre-commit
concom validate --file "$1"
```

### Next Version
concom determines the semantic version of the next release by looking at the
existing tags and the since made commits. To do this, there must be at least
one tag already, as there is no way to guess the maturity of the project.
Given that your project is still in the 'initial development' phase (major
version 0) breaking changes won't increment the major version
yet. You must therefore manually tag it as 1.0.0 when you are ready.

```bash
# making a new tag
git tag "$(concom next-version)"
```

example
```bash
# current tags
$ git tag
1.0.0
1.0.1

# since made commits
$ git log --oneline 1.0.1..HEAD
<sha> feat(X): some feature around X
<sha> fix(Y): damn Y was broken

$ concom next-version
1.1.0
```

#### Dev Tags

The above example assume that tags were made on *main* and *HEAD* is also pointing
at it. But the tags that are used for evaulation MUST be reachable from *HEAD*. Example:

```
     1.0.0                 2.0.0
----(feat)---(breaking)---(feat)---    main 
     \
      \                ?
       \---(feat)---(feat)             some-branch|HEAD
```
'?' will be evaluated to 1.1.0 since 2.0.0 is not reachable from HEAD. To
perform a dev tag on that branch one can therefore simply do:

```bash
# create a tag of format: <Major>.<Minor>.<Patch>-dev+<Short-Sha>
git tag "$(comcon next-version)-dev+$(git rev-parse --short HEAD)"
```

All non release tags won't play a role in the calculation of the next-version.

#### About v\*.\*.\*
v1.1.1 is not a valid semantic version (as mentioned [here](https://semver.org/#is-v123-a-semantic-version))
but if you want to determine the next version automatically anyways one can do:

```bash
git tag | cut -c 2- | concom next-version --from-stdin
```

Note: the tags provided this way will be checked for them being reachable from HEAD as well.

### Development

```bash
git clone <repo> <dest>
cd <dest>
# we don't need to get everything as we only need this for the header files
# or when you want to build libgit2 yourself
git submodule --update --init --recursive --filter=tree:0
```

#### Building

```bash
# build concom with libgit2 pre-built as static library
zig build -Dlibgit2-object=/path/to/libgit2.a -Dlibgit2-version v1.7.2

# build concom using the script 'build-libgit2' to build
# libgit2 (the build will be cached but requires docker to be installed)
zig build
```

## TODO
- narrow the error's atm. every is '!...'
- use @embedFile to get the usage?
