/**
    TBD.

    Authors: Simon Peter Campbell, peter@spcampbell.co.uk
    Copyright: MIT
*/
module denjin.rendering.traits.assets;

// Engine.
import denjin.rendering.ids;

template isAssets (T)
{
    
    enum isAssets = true;
}

template isMesh (T)
{

    enum isMesh = true;
}