module denjin.crap;
import glad;

bool load()
{
    gladLoadGL();
    auto i = GLuint();
    return true;
}

unittest
{
    assert (load);
}