/* SPDX-License-Identifier: Zlib */

/**
 * Upstream Cache
 *
 * Path mangling for retention of sources
 *
 * Authors: © 2020-2022 Serpent OS Developers
 * License: ZLib
 */

module boulder.upstreamcache;

import moss.core.util : hardLinkOrCopy;
import std.exception : enforce;
import std.conv : to;
import std.path : buildPath, dirName;
import std.file : exists, mkdirRecurse, rename;
import std.string : format;
public import moss.format.source.upstream_definition;

/**
 * The UpstreamCache provides persistent paths and
 * deduplication facilities to permit retention of
 * hash-indexed downloads across multiple builds.
 */
public final class UpstreamCache
{

    /**
     * Only allow Boulder to construct us.
     */
    package this()
    {

    }

    /**
     * Construct all required directories
     */
    void constructDirs()
    {
        auto paths = [
            rootDirectory, stagingDirectory, gitDirectory, plainDirectory
        ];
        foreach (p; paths)
        {
            p.mkdirRecurse();
        }
    }

    /**
     * Returns: True if the final destination exists
     */
    bool contains(in UpstreamDefinition def) @safe
    {
        return finalPath(def).exists;
    }

    /** 
     *  Promote from staging to real
     */
    void promote(in UpstreamDefinition def) @safe
    {
        auto st = stagingPath(def);
        auto fp = finalPath(def);
        enforce(def.type == UpstreamType.Plain, "UpstreamCache: git not yet supported");
        enforce(st.exists, "UpstreamCache.promote(): %s does not exist".format(st));

        /* Move from staging path to final path */
        auto dirn = fp.dirName;
        dirn.mkdirRecurse();
        st.rename(fp);
    }

    /**
     * Promote the shared upstream into a target tree using hardlink or copy.
     */
    void share(in UpstreamDefinition def, in string destPath) @safe
    {
        auto fp = finalPath(def);
        enforce(def.type == UpstreamType.Plain, "UpstreamCache: git not yet supported");
        hardLinkOrCopy(fp, destPath);
    }

    /**
     * Return the staging path for the definition
     */
    const(string) stagingPath(in UpstreamDefinition def) @trusted
    {
        enforce(def.type == UpstreamType.Plain, "UpstreamCache: git not yet supported");
        enforce(def.plain.hash.length >= 5,
                "UpstreamCache: Hash too short: " ~ to!string(def.plain));
        return stagingDirectory.buildPath(def.plain.hash);
    }

    /**
     * Return the final path for the definition
     */
    const(string) finalPath(in UpstreamDefinition def) @trusted
    {
        enforce(def.type == UpstreamType.Plain, "UpstreamCache: git not yet supported");
        enforce(def.plain.hash.length >= 5,
                "UpstreamCache: Hash too short: " ~ to!string(def.plain));

        return plainDirectory.buildPath(def.plain.hash[0 .. 5],
                def.plain.hash[5 .. $], def.plain.hash);
    }

private:

    /**
     * Base of all directories
     */
    static immutable(string) rootDirectory = "/var/cache/boulder/upstreams";

    /**
     * Staging downloads that might be wonky.
     */
    static immutable(string) stagingDirectory = rootDirectory.buildPath("staging");

    /**
     * Git clones
     */
    static immutable(string) gitDirectory = rootDirectory.buildPath("git");

    /**
     * Plain downloads
     */
    static immutable(string) plainDirectory = rootDirectory.buildPath("fetched");
}