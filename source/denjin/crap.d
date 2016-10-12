module denjin.crap;
import glad;

bool load()
{
    gladLoadGL();
    auto i = GLuint();
    glGenBuffers(1, &i);
    glDeleteBuffers(1, &i);
    return true;
}

unittest
{
    assert (load);
}