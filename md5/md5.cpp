#include <iostream>
#include <string>

#pragma comment(lib,"md5.lib")

extern "C" __declspec(dllimport) char* _stdcall md5(const char* res, int lenght);

int main() {
    
    std::string input;
    std::cout << "Input: ";
    std::getline(std::cin, input);

    std::string hash = md5(input.c_str(), input.length());

    std::cout << "Hash: " << hash << std::endl;
}
